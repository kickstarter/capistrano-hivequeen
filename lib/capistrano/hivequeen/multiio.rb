# Keeps an in-memory history of printed lines (to persist to HQ),
# and puts to stderr (capistrano's default)
class HiveQueen
  class MultiIO
    require 'stringio'

    def initialize(output = $stderr)
      @memory = StringIO.new
      @output = output
    end

    def puts(msg)
      [@memory, @output].each{|t| t.puts(msg)}
    end

    # Read the history from memory
    def history
      @memory.rewind
      @memory.read
    end

    def tty?
      [@memory, @output].all?(&:tty?)
    end

  end
end
