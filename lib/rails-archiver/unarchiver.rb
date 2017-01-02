# Class that loads a tree hash of objects representing ActiveRecord classes.
# We will use the models in the codebase to determine how to import them.

require 'activerecord-import'
require 'active_support/ordered_hash'

module RailsArchiver
  class Unarchiver

    class ImportError < StandardError; end

    attr_accessor :errors, :transport

    # @param model [ActiveRecord::Base]
    # @param options [Hash]
    #   * logger [Logger]
    #   * new_copy [Boolean] if true, create all new objects instead of
    #                        replacing existing ones.
    #   * crash_on_errors [Boolean] if true, do not do any imports if any
    #                               models' validations failed.
    def initialize(model, options={})
      @model = model
      @logger = options.delete(:logger) || Logger.new(STDOUT)
      # map of objects to import: class => list of objects
      @import_objects = {}
      # Do a direct copy, i.e. no mapping
      @new_copy = options.delete(:new_copy)
      # class -> {old ID -> new ID} for new copies
      @id_mapping = {}
      # Transport for downloading
      @options = options
      self.transport = _get_transport(options.delete(:transport) || :in_memory)
      self.errors = []
    end

    # Unarchive a model.
    def unarchive
      @errors = []
      @logger.info('Downloading JSON file')
      hash = @transport.retrieve_archive
      @logger.info("Loading #{@model.class.name}")
      load_classes(hash)
      if @model.attribute_names.include?('archived')
        @model.update_attribute(:archived, false)
      end
      @logger.info("#{@model.class.name} load complete!")
    end

    # Load a list of general classes that were saved as JSON.
    # @param hash [Hash]
    def load_classes(hash)
      old_record_timestamps = ActiveRecord::Base.record_timestamps
      ActiveRecord::Base.record_timestamps = false
      full_hash = hash.with_indifferent_access
      full_hash.each do |key, vals|
        save_models(key.constantize, vals)
      end
      if @options[:crash_on_errors] && self.errors.any?
        raise ImportError.new("Errors occurred during load - please see 'errors' method for more details")
      end
      order_classes(@import_objects.keys).each do |klass|
        models = @import_objects[klass]
        next if models.empty?
        process_associations(klass, models) if @new_copy
        import_objects(klass, models)
      end
    ensure
      ActiveRecord::Base.record_timestamps = old_record_timestamps
    end

    # Reorder the classes before import. We need to do this if any earlier
    # classes depend on later ones.
    # @param classes [Array<Class>]
    # @return [Array<Class>] the ordered array.
    def order_classes(classes)
      results = []

      # 1. Look at each class. Add it to the end of the array.
      # 2. Inspect the belongs_to associations for that class.
      # 3. Ensure that the belongs_to class is before this one. If it already
      # exists, then it's already before this one since we're adding to the end.
      # If it doesn't exist yet, insert it just before this class.
      # This will ensure that all belongs_to associations will be inserted
      # before the models that belong to it.

      classes.reverse.each do |klass|
        results << klass
        klass.reflect_on_all_associations(:belongs_to).each do |assoc|
          next unless @import_objects.keys.include?(assoc.klass)
          results.insert(-2, assoc.klass) unless results.include?(assoc.klass)
        end
      end
      results
    end

    # Used for new copies. Replace all foreign keys in the models with the
    # new IDs that were previously imported.
    # @param klass [Class]
    # @param models [Array<ActiveRecord::Base>]
    def process_associations(klass, models)
      klass.reflect_on_all_associations(:belongs_to).each do |assoc|
        id_mapping = @id_mapping[assoc.klass]
        if id_mapping
          key = assoc.foreign_key
          models.each do |model|
            new_key = id_mapping[model[key]]
            model[key] = new_key if new_key
          end
        end
      end
    end

    # Save all models into memory in the given hash on the given class.
    # @param klass [Class] the starting class.
    # @param hashes [Array<Hash<] the object hashes to import.
    def save_models(klass, hashes)
      hashes.each do |hash|
        if @new_copy
          hash = before_init(klass, hash)
          model = init_model(klass, hash)
          next unless after_init(model, hash)
        else
          model = init_model(klass, hash)
        end

        # Non-id primary keys will swallow the primary key from the hash
        if klass.primary_key != 'id'
          existing = klass.where(klass.primary_key => attrs[klass.primary_key]).first
          return existing if existing # create will fail with duplicate key
          model.send("#{klass.primary_key}=", attrs[klass.primary_key])
        end

        if @new_copy && model.invalid?
          self.errors << "#{klass.name} #{hash['id']} could not be loaded: #{model.errors.full_messages.join("\n")}"
          next
        end
        @import_objects[klass] ||= []
        @import_objects[klass] << model
      end
    end

    # Import saved objects.
    # @param klass [Class]
    # @param models [Array<ActiveRecord::Base>]
    def import_objects(klass, models)
      cols_to_update = klass.column_names - [klass.primary_key]
      # check other unique indexes
      indexes = ActiveRecord::Base.connection.indexes(klass.table_name).
        select { |i|i['unique']}
      indexes.each { |index| cols_to_update -= index.columns }
      options = { :validate => false, :on_duplicate_key_update => cols_to_update }

      @logger.info("Importing #{models.length} for #{klass.name}")
      models.in_groups_of(1000).each do |group|
        models_to_import = group.compact
        import_proc = Proc.new { klass.import(models_to_import, options) }
        if @new_copy
          # save the old IDs, do the import, then map the new IDs to the old ones
          update_ids(models_to_import, &import_proc)
        else
          # just do the import
          import_proc.call
        end
      end
    rescue => e
      self.errors << "Error importing class #{klass.name}: #{e.message}"
    end

    # Do an import and update the IDs of the models after the import is done.
    # @param models [Array<ActiveRecord::Base>]
    def update_ids(models)
      klass = models.first.class
      old_ids = models.map(&:id)
      mapping = @id_mapping[klass] ||= {}
      yield

      # update IDs for MySQL only - Postgres and SQLite are already supported
      # with newer activerecord-import versions.
      #### NOTE: Only works with InnoDB tables and
      #### when innodb_autoinc_lock_mode is set to 0 or 1 - see
      #### https://github.com/zdennis/activerecord-import/pull/279
      if ActiveRecord::Base.connection.adapter_name.downcase =~ /mysql/
        id = ActiveRecord::Base.connection.select_value('SELECT LAST_INSERT_ID()')
        models.each_with_index do |model, i|
          model.id = id + i
        end
      end

      models.each_with_index do |model, i|
        mapping[old_ids[i]] ||= model.id
      end
    end

    def init_model(klass, hash)
      attrs = hash.select do |x|
        klass.column_names.include?(x) && x != klass.primary_key
      end

      if @new_copy
        attrs = before_init(klass, attrs)
        model = klass.new
        # for attr_protected
        model.send(:attributes=, attrs, false)
        after_init(model, attrs)
      else
        model = klass.where(klass.primary_key => hash[klass.primary_key]).first
        if model.nil?
          model = klass.new
          model.send(:attributes=, attrs, false)
          # can't set this in the attribute hash, it'll be overridden. Need
          # to set it manually.
          model[klass.primary_key] = hash[klass.primary_key]
        else
          model.send(:attributes=, attrs, false)
        end
      end

      # for some reason activerecord-import doesn't handle time zones correctly
      # for older versions
      model.attributes.each do |key, val|
        if val.respond_to?(:utc)
          model[key] = val.utc
        end
      end

      model
    end

    protected

    # Any special handling of classes and attribute hashes should happen here.
    # @param klass [Class] the class we want to instantiate.
    # @param attrs [HashWithIndifferentAccess] the attributes we want to
    #   instantiate it with. They can/should be manipulated here.
    def before_init(klass, attrs)
    end

    # Special handling of models after they have been instantiated, before
    # we attempt to save it.
    # @param model [ActiveRecord::Base] the record we have just instantiated.
    # @param attrs [Hash] the original attributes set to the model.
    # @return [Boolean] true to continue with the model, false to swallow it.
    def after_init(model, attrs)
      true
    end

    # Get associations for the class.
    # @param klass [Class] the ActiveRecord class.
    # @param model [ActiveRecord::Base] the model we've already instantiated.
    # @param hash [Hash] the attribute hash we are using.
    def get_associations(klass, model, hash)
      klass.reflect_on_all_associations
    end

    private

    def _get_transport(symbol_or_object)
      if symbol_or_object.is_a?(Symbol)
        klass = if symbol_or_object.present?
                  "RailsArchiver::Transport::#{symbol_or_object.to_s.classify}".constantize
                  else
                    Transport::InMemory
                end
        klass.new(@model, @logger)
      else
        symbol_or_object
      end
    end

  end
end
