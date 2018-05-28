# Abstract class that represents a way to store and retrieve the generated
# JSON object.
module RailsArchiver
  module Transport
    class Base

      # @param model [ActiveRecord::Base] the model we will be working with.
      # @param logger [Logger]
      def initialize(model=nil, logger=nil)
        @model = model
        @options = {}
        @logger = logger || ::Logger.new(STDOUT)
      end

      # @param options [Hash] A set of options to work with.
      def configure(options)
        @options = options
      end

      # To be implemented by subclasses. Store the archive somewhere to be retrieved
      # later. You should also be storing the location somewhere such as on the
      # model. Use @model to reference it.
      # @param hash [Hash] the hash to store. Generally you'll want to use
      # .to_json on it.
      def store_archive(hash)
        raise NotImplementedError
      end

      # To be implemented by subclasses. Retrieve the archive that was previously
      # created.
      # @param location [String] if given, the location of the archive (e.g.
      # S3 key). Otherwise will be figured out from the existing model
      # in the database.
      # @return [Hash] the retrieved hash.
      def retrieve_archive(location=nil)
        raise NotImplementedError
      end

    end
  end
end
