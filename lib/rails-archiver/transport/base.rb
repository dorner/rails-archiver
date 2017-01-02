# Abstract class that represents a way to store and retrieve the generated
# JSON object.
module RailsArchiver
  module Transport
    class Base

      # @param model [ActiveRecord::Base] the model we will be working with.
      def initialize(model, logger=nil)
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
      # @return [Hash] the retrieved hash.
      def retrieve_archive
        raise NotImplementedError
      end

    end
  end
end
