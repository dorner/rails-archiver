# Class that loads a tree hash of objects representing ActiveRecord classes.
# We will use the models in the codebase to determine how to import them.

require 'activerecord-import'

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
      @options = options
      # Transport for downloading
      self.transport = _get_transport(options.delete(:transport) || :in_memory)
      self.errors = []
    end

    # Unarchive a model.
    # @param location [String] if given, uses the given location to unarchive.
    # Otherwise uses the existing model in the database (e.g. attribute on the
    # model) depending on the transport being used.
    def unarchive(location=nil)
      @errors = []
      source = @model ? @model.class.name : location
      @logger.info('Downloading JSON file')
      hash = @transport.retrieve_archive(location)
      @logger.info("Loading #{source}")
      load_classes(hash)
      if @model
        @model.reload
        if @model.attribute_names.include?('archived')
          @model.update_attribute(:archived, false)
        end
      end
      @logger.info("#{source} load complete!")
    end

    # Load a list of general classes that were saved as JSON.
    # @param hash [Hash]
    def load_classes(hash)
      full_hash = hash.with_indifferent_access
      full_hash.each do |key, vals|
        save_models(key.constantize, vals)
      end
      if @options[:crash_on_errors] && self.errors.any?
        raise ImportError.new("Errors occurred during load - please see 'errors' method for more details")
      end
    end

    # Save all models into memory in the given hash on the given class.
    # @param klass [Class] the starting class.
    # @param hashes [Array<Hash<] the object hashes to import.
    def save_models(klass, hashes)
      models = hashes.map { |hash| init_model(klass, hash) }
      import_objects(klass, models)
    end

    # Import saved objects.
    # @param klass [Class]
    # @param models [Array<ActiveRecord::Base>]
    def import_objects(klass, models)
      cols_to_update = klass.column_names - [klass.primary_key]
      # check other unique indexes
      indexes = ActiveRecord::Base.connection.indexes(klass.table_name).
        select(&:unique)
      indexes.each { |index| cols_to_update -= index.columns }
      options = { :validate => false, :timestamps => false,
                  :on_duplicate_key_update => cols_to_update }

      @logger.info("Importing #{models.length} for #{klass.name}")
      models.in_groups_of(1000).each do |group|
        klass.import(group.compact, options)
      end
    rescue => e
      self.errors << "Error importing class #{klass.name}: #{e.message}"
    end

    def init_model(klass, hash)
      attrs = hash.select do |x|
        klass.column_names.include?(x) && x != klass.primary_key
      end

      # fix time zone issues
      klass.columns.each do |col|
        if col.type == :datetime && attrs[col.name]
          attrs[col.name] = Time.zone.parse(attrs[col.name])
        end
      end

      model = klass.where(klass.primary_key => hash[klass.primary_key]).first
      if model.nil?
        model = klass.new
        _assign_attributes(model, attrs)
        # can't set this in the attribute hash, it'll be overridden. Need
        # to set it manually.
        model[klass.primary_key] = hash[klass.primary_key]
      else
        _assign_attributes(model, attrs)
      end

      model
    end

    private

    # @param model [ActiveRecord::Base]
    # @param attrs [Hash]
    def _assign_attributes(model, attrs)
      if model.method(:attributes=).arity == 1
        model.attributes = attrs
      else
        model.send(:attributes=, attrs, false)
      end
    end

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
