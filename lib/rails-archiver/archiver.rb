require 'tmpdir'
# Takes a database model and:
# 1) Visits all dependent associations
# 2) Saves everything in one giant JSON hash
# 3) Uploads the hash as configured
# 4) Deletes all current records from the database
# 5) Marks model as archived
module RailsArchiver
  class Archiver

    # Hash which determines equality solely based on the id key.
    class IDHash < Hash
      def ==(other)
        self[:id] == other[:id]
      end
    end

    attr_accessor :transport, :archive_location

    # Create a new Archiver with the given model.
    # @param model [ActiveRecord::Base] the model to archive or unarchive.
    # @param options [Hash]
    #   * logger [Logger]
    #   * transport [Sybmol] :in_memory or :s3 right now
    #   * delete_records [Boolean] whether or not we should delete existing
    #     records
    def initialize(model, options={})
      @model = model
      @logger = options.delete(:logger) || ::Logger.new(STDOUT)
      @hash = {}
      self.transport = _get_transport(options.delete(:transport) || :in_memory)
      @options = options
      # hash of table name -> IDs to delete in that table
      @ids_to_delete = {}
    end

    # Archive a model.
    # @return [Hash] the hash that was archived.
    def archive
      @logger.info("Starting archive of #{@model.class.name} #{@model.id}")
      @hash = {}
      _visit_association(@model)
      @logger.info('Completed loading data')
      @archive_location = @transport.store_archive(@hash)
      if @model.attribute_names.include?('archived')
        @model.update_attribute(:archived, true)
      end
      @logger.info('Deleting rows')
      _delete_records if @options[:delete_records]
      @logger.info('All records deleted')
      @hash
    end

    # Returns a single object in the database represented as a hash.
    # Does not account for any associations, only prints out the columns
    # associated with the object as they relate to the current schema.
    # Can be extended but should not be overridden or called explicitly.
    # @param node [ActiveRecord::Base] an object that inherits from AR::Base
    # @return [Hash]
    def visit(node)
      return {} unless node.class.respond_to?(:column_names)
       if @options[:delete_records] && node != @model
        @ids_to_delete[node.class.table_name] ||= Set.new
        @ids_to_delete[node.class.table_name] << node.id
      end
      IDHash[
        node.class.column_names.select do |cn|
          next unless node.respond_to?(cn)
          # Only export columns that we actually have data for
          !node[cn].nil?
        end.map do |cn|
          [cn.to_sym, node[cn]]
        end
      ]
    end

    # Delete rows from a table. Can be used in #delete_records.
    # @param table [String] the table name.
    # @param ids [Array<Integer>] the IDs to delete.
    def delete_from_table(table, ids)
      return if ids.blank?
      @logger.info("Deleting #{ids.size} records from #{table}")
      groups = ids.to_a.in_groups_of(10000)
      groups.each_with_index do |group, i|
        sleep(0.5) if i > 0 # throttle so we don't kill the DB
        delete_query = <<-SQL
          DELETE FROM `#{table}` WHERE `id` IN (#{group.compact.join(',')})
        SQL
        ActiveRecord::Base.connection.delete(delete_query)
      end

      @logger.info("Finished deleting from #{table}")
    end

    protected

    # Callback that runs after deletion is finished.
    def after_delete
    end

    # Indicate which associations to retrieve from the given model.
    # @param node [ActiveRecord::Base]
    def get_associations(node)
      node.class.reflect_on_all_associations.select do |assoc|
        [:destroy, :delete_all].include?(assoc.options[:dependent]) &&
          [:has_many, :has_one].include?(assoc.macro)
      end
    end

    private

    # Delete the records corresponding to the model.
    def _delete_records
      @ids_to_delete.each do |table, ids|
        delete_from_table(table, ids)
      end
    end

    # @param symbol_or_object [Symbol|RailsArchiver::Transport::Base]
    # @return [RailsArchiver::Transport::Base]
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

    # Used to visit an association, and recursively calls down to
    # all child objects through all other allowed associations.
    # @param node [ActiveRecord::Base|Array<ActiveRecord::Base>]
    #    any object(s) that inherits from ActiveRecord::Base
    def _visit_association(node)
      return if node.blank?
      if node.respond_to?(:each) # e.g. a list of nodes from a has_many association
        node.each { |n| _visit_association(n) }
      else
        class_name = node.class.name
        @hash[class_name] ||= Set.new
        @hash[class_name] << visit(node)
        get_associations(node).each do |assoc|
          @logger.debug("Visiting #{assoc.name}")
          new_nodes = node.send(assoc.name)
          next if new_nodes.blank?

          if new_nodes.respond_to?(:find_each)
            new_nodes.find_each { |n| _visit_association(n) }
          else
            _visit_association(new_nodes)
          end
        end

      end
    end
  end
end
