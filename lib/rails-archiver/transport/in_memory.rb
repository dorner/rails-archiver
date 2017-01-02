# Transport that just stores and retrieves the hash in memory.
module RailsArchiver
  module Transport
    class InMemory < Base

      def store_archive(json)
        @options[:json] = json
        'some-key-here'
      end

      def retrieve_archive
        @options[:json]
      end

    end
  end
end
