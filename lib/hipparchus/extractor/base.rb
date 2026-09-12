# frozen_string_literal: true

module Hipparchus
  module Extractor
    # Abstract base for concrete extractors.
    #
    # Subclasses implement exactly one public method, {#call}, returning a
    # {Hipparchus::IR::Schema}. The two connections are stored for their use:
    #
    # * +@connection+     - ActiveRecord connection; adapter identity + metadata.
    # * +@raw_connection+ - driver connection; catalog queries.
    class Base
      # @param connection [Object] an ActiveRecord connection
      # @param raw_connection [Object] the underlying driver connection
      def initialize(connection, raw_connection)
        @connection = connection
        @raw_connection = raw_connection
      end

      # @return [Hipparchus::IR::Schema]
      def call
        raise NotImplementedError, "#{self.class} must implement #call"
      end
    end
  end
end
