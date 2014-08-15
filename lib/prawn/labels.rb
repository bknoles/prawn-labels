# labels.rb :  A simple helper to generate labels for Prawn PDFs
#
# Copyright February 2010, Jordan Byron. All Rights Reserved.
#
# This is free software. Please see the LICENSE and COPYING files for details.

require 'prawn'
require 'yaml'

module Prawn
  class Labels
    attr_reader :document, :type

    class << self

      def generate(file_name, data, options = {}, &block)
        labels = Labels.new(data, options, &block)
        labels.document.render_file(file_name)
      end

      def render(data, options = {}, &block)
        labels = Labels.new(data, options, &block)
        labels.document.render
      end

      def types=(custom_types)
        if custom_types.is_a? Hash
          types.merge! custom_types
        elsif custom_types.is_a?(String) && File.exist?(custom_types)
          types.merge! YAML.load_file(custom_types)
        end
      end

      def types
        @types ||= begin
          types_file = File.join(File.dirname(__FILE__), 'types.yaml')
          YAML.load_file(types_file)
        end
      end

    end

    def initialize(data, options = {}, &block)
      unless @type = Labels.types[options[:type]]
        raise "Label Type Unknown '#{options[:type]}'"
      end

      type["paper_size"]  ||= "A4"
      type["top_margin"]  ||= 36
      type["left_margin"] ||= 36
      
      options[:document] ||= {}
      
      options.merge!(:vertical_text => true) if type["vertical_text"]

      @document = Document.new  options[:document].merge(
                                :page_size      => type["paper_size"],
                                :top_margin     => type["top_margin"],
                                :bottom_margin  => type["bottom_margin"],
                                :left_margin    => type["left_margin"],
                                :right_margin   => type["right_margin"])

      @document.font options[:font_path] if options[:font_path]
                                
      generate_grid @type

      data.each_with_index do |record, index|
        if (defined? record.vertical_text)
          options.merge!(:vertical_text => record.vertical_text)
        end
        create_label(index, record, options) do |pdf, record|
          yield pdf, record
        end
      end

    end

    private

    def generate_grid(type)
      @document.define_grid({ :columns       => type["columns"],
                              :rows          => type["rows"],
                              :column_gutter => type["column_gutter"],
                              :row_gutter    => type["row_gutter"]
                            })
    end

    def row_col_from_index(index)
      page, new_index = index.divmod(@document.grid.rows * @document.grid.columns)
      if new_index == 0 and page > 0
        @document.start_new_page
        generate_grid @type
        return [0,0]
      end
      return new_index.divmod(@document.grid.columns)
    end

    def create_label(index, record, options = {},  &block)
      p = row_col_from_index(index)

      shrink_text(record) if options[:shrink_to_fit] == true

      b = @document.grid(p.first, p.last)

      if options[:vertical_text]
        @document.rotate(270, :origin => b.top_left) do
          @document.translate(0, b.width) do
            @document.bounding_box b.top_left, :width => b.height, :height => b.width do
              yield @document, record
            end
          end
        end
      else
        #Shrink text if our label doesn't fit vertically within the bounding box
        @document.font_size = options[:font_size] if options[:font_size]        
        while text_height(record, b.width) > b.height
          @document.font_size -= 1
        end
        @document.bounding_box b.top_left, :width => b.width, :height => b.height do
        
          #@document.stroke_bounds
          @document.bounding_box(
            label_top_left(record, b.width, b.height, b.top_left), 
            :width => text_width(record, b.width) + width_buffer, 
            :height => text_height(record, b.width)
          ) do
            #@document.stroke_bounds
            yield @document, record
          end
        end
      end

    end

    def shrink_text(record)
      linecount = (split_lines = record.split("\n")).length

      # 30 is estimated max character length per line.
      split_lines.each {|line| linecount += line.length / 30 }

      # -10 accounts for the overflow margins
      rowheight = @document.grid.row_height - 10

      if linecount <= rowheight / 12.floor
        @document.font_size = 12
      else
        @document.font_size = rowheight / (linecount + 1)
      end
    end

    # Calculate the top left of each label based on height and width of the bounding box.
    # This will center the bounding box horizontally and vertically within the grid cell
    def label_top_left(record, box_width, box_height, box_top_left)
      left = box_top_left[0] + (box_width - text_width(record, box_width))/2 - width_buffer
      right = box_top_left[1] - (box_height - text_height(record, box_width))/2 - height_buffer
      [left, right]
    end

    def text_width(record, box_width)
      split_lines = record.split("\n")

      # Chop words off of lines which exceed the box width until they fit within the box
      split_lines.each_with_index do |line, i|
        if @document.width_of(line, size: @document.font_size) > box_width
          while @document.width_of(line, size: @document.font_size) > box_width
            line = line[0...line.rindex(' ')]
          end
          split_lines[i] = line
        end
      end   

      longest_line = split_lines.inject do |mem_obj, line|
        @document.width_of(line, size: @document.font_size) > 
        @document.width_of(mem_obj, size: @document.font_size) ? line : mem_obj
      end

      @document.width_of(longest_line,  size: @document.font_size)
    end

    # Determine the height of the text for a given bounding box width
    def text_height(record, box_width)
      fake_text = ""
      num_lines = number_of_lines(record, box_width)
      num_lines.times do
        fake_text += "Fake\n"
      end
      @document.height_of(fake_text)
    end
    
    # Determine the number of lines that a record will use given the bounding box width
    def number_of_lines(record, box_width)
      split_lines = record.split("\n")

      extra_lines = 0
      split_lines.each do |line|
        if @document.width_of(line, size: @document.font_size) > box_width
          extra_lines += 1
        end
      end

      split_lines.length + extra_lines
    end

    # A buffer value to ensure that text doesn't overflow our bounding box
    def width_buffer; 5; end
    def height_buffer; 5; end

  end
end
