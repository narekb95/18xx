# frozen_string_literal: true

module Engine
  module Part
    class Node < Base
      attr_accessor :lanes

      def clear!
        @paths = nil
        @exits = nil
      end

      def solo?
        @tile.nodes.one?
      end

      def paths
        @paths ||= @tile.paths.select { |p| p.nodes.any? { |n| n == self } }
      end

      def exits
        @exits ||= paths.flat_map(&:exits)
      end

      def rect?
        false
      end

      def select(paths, corporation: nil)
        on = paths.map { |p| [p, 0] }.to_h

        walk(on: on, corporation: corporation) do |path|
          on[path] = 1 if on[path]
        end

        on.keys.select { |p| on[p] == 1 }
      end

      # Explore the paths and nodes reachable from this node
      #
      # visited: a hashset of visited Nodes
      # visited_paths: a hashset of visited Paths
      # on: see Path::Walk
      # corporation: If set don't walk on adjacent nodes which are blocked for the passed corporation
      # skip_track: If passed, don't walk on track of that type (ie: :broad track for 1873)
      #
      # This method recursively bubbles up yielded values from nested Node::Walk and Path::Walk calls
      def walk(visited: {}, on: nil, corporation: nil, visited_paths: {}, skip_track: nil, tile_type: :normal)
        return if visited[self]

        visited[self] = true

        paths.each do |node_path|
          next if node_path.track == skip_track

          node_path.walk(visited: visited_paths, on: on, tile_type: tile_type) do |path, vp|
            yield path
            next if path.terminal?

            path.nodes.each do |next_node|
              next if next_node == self
              next if corporation && next_node.blocks?(corporation)

              next_node.walk(
                visited: visited,
                on: on,
                corporation: corporation,
                visited_paths: vp,
                skip_track: skip_track,
                tile_type: tile_type
              ) { |p| yield p }
            end
          end
        end

        visited.delete(self) unless tile_type == :lawson
      end
    end
  end
end
