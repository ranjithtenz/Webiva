
class UserSegment::OperationBuilder < HashModel
  attributes :operator => nil, :field => nil, :operation => nil, :arguments => nil, :condition => nil, :parent => nil

  def strict?; true; end
  def arguments; @arguments ||= []; end

  def operator_options
    [['Not', 'not'], ['', nil]]
  end

  def condition_options
    [['', nil], ['And', 'and'], ['Or', 'or'], ['With', 'with']]
  end

  def validate
    self.errors.add(:field, 'is invalid') unless self.user_segment_field.valid?
    self.errors.add(:condition, 'is invalid') if ! self.condition.blank? && ! self.child_field.valid?
  end

  def build(opts={})
    self.operator = opts[:operator]
    self.field = opts[:field]
    self.operation = opts[:operation]
    self.condition = opts[:condition]
    self.parent = opts[:parent]
    unless self.field.blank?
      unless self.operation_options.rassoc(self.operation)
        self.operation = self.operation_options[0][1]
        @user_segment_field = nil
      end
    end

    self.operation_arguments.each_with_index do |type, idx|
      arg = "argument#{idx}"
      self.send("#{arg}=", opts[arg.to_sym]) if opts[arg.to_sym]
    end

    if ! self.condition.blank?
      parent = self.condition == 'and' ? self : nil
      child = (opts[:child] || {}).merge(:parent => parent)
      self.child_field.build(child)
      self.user_segment_field.child = self.child_field.user_segment_field.to_h if self.condition == 'and'
    end
  end

  def field_options
    return @field_options if @field_options
    @field_options = []
    UserSegment::FieldHandler.handlers.each do |handler|
      if self.parent.nil? || self.parent.user_segment_field.handler == handler
        handler[:class].user_segment_fields.each do |field, values|
          @field_options << [values[:name], field.to_s] unless @field_options.rassoc(field.to_s)
        end
      end
    end
    @field_options = [['Select a field', nil]] + @field_options.sort { |a, b| a[0] <=> b[0] }
  end

  def user_segment_field
    return @user_segment_field if @user_segment_field
    @user_segment_field = UserSegment::Field.new :field => self.field, :operation => self.operation, :arguments => self.arguments
  end

  def operation_options
    return @operation_options if @operation_options
    @operation_options = []

    if self.user_segment_field.type_class
      @operation_options = self.user_segment_field.type_class.user_segment_field_type_operations.collect do |operation, values|
        [values[:name], operation.to_s]
      end
    end

    @operation_options.sort! { |a, b| a[0] <=> b[0] }
    @operation_options
  end

  def operation_arguments
    self.user_segment_field.operation_arguments || []
  end

  def operation_argument_names
    self.user_segment_field.operation_argument_names
  end

  def operation_argument_options
    self.user_segment_field.operation_argument_options
  end

  def convert_to(value, idx)
    UserSegment::FieldType.convert_to(value, self.operation_arguments[idx], self.operation_argument_options[idx])
  end

  def method_missing(arg, *args)
    arg = arg.to_s
    if arg =~ /^argument(\d+)$/
      self.arguments[$1.to_i]
    elsif arg =~ /^argument(\d+)=$/
      self.arguments[$1.to_i] = self.convert_to(args[0], $1.to_i) if $1.to_i < self.operation_arguments.length
    else
      super
    end
  end

  def to_expr
    return '' unless self.valid?
    output = self.operator == 'not' ? 'not ' : ''
    output += self.user_segment_field.to_expr(:nochild => 1)
    output += '.' + self.child_field.to_expr if self.condition == 'and'
    output += ' + ' + self.child_field.to_expr if self.condition == 'or'
    output += "\n" + self.child_field.to_expr if self.condition == 'with'
    output
  end

  def child_field
    @child_field ||= UserSegment::OperationBuilder.new nil
  end
end
