require "net/ftw/namespace"

# Protocol state machine
class Net::FTW::Machine
  class InvalidTransition < StandardError
    public
    def initialize(instance, current_state, next_state)
      @instance = instance
      @current_state = current_state
      @next_state = next_state
    end

    public
    def to_s
      return "Invalid transition: #{@current_state} => #{@next_state} on object: #{instance}"
    end
  end # class InvalidTransition

  # Always the first state.
  START = :start
  ERROR = :error

  public
  def initialize
    @state = START
  end # def initialize

  # Feed data input into this machine
  public
  def feed(input)
    # Invoke whatever method of state we are in when we have data.
    # like state_headers(input), etc
    method("state_#{@state}")(input)
  end # def feed

  public
  def state?(state)
    return @state == state
  end # def state?

  public
  def transition(new_state)
    if valid_transition?(new_state)
      @state = new_state
    else
      raise InvalidTransition.new(@state, new_state, self.class)
    end
  end # def transition

  public
  def valid_transition?(new_state)
    allowed = TRANSITIONS[@state]
    if allowed.is_a?(Array)
      return allowed.include?(new_state)
    else
      return allowed == new_state
    end
  end # def valid_transition
end # class Net:FTW::Machine
