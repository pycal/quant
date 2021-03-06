# == Schema Information
#
# Table name: weights
#
#  id          :integer          not null, primary key
#  type        :string(255)
#  user_id     :integer
#  bmi         :float
#  value       :float
#  lean_mass   :float
#  fat_mass    :float
#  fat_percent :float
#  date        :datetime
#  created_at  :datetime
#  updated_at  :datetime
#  meta        :hstore
#  source      :string(255)
#

class Weight < ActiveRecord::Base
  attr_accessible :value, :date, :lean_mass, :fat_mass, :fat_percent,
                  :source, :meta

  # We use this to store provider-specific metadata about the weight. In the case of withings,
  # we get a pkey called grpid that is useful for maintaining a single copy of each record.
  store_accessor :meta, :grpid

  belongs_to :user

  validates :value, presence: true, numericality: true
  validates :lean_mass, numericality: true, allow_nil: true
  validates :fat_mass, numericality: true, allow_nil: true
  validates :fat_percent, numericality: true, allow_nil: true
  validates :date, presence: true

  before_save :calculate_all_known_values

  def self.current
    order("date DESC").first
  end

  def self.most_recent(count)
    order("date DESC").limit(count)
  end

  def calculate_all_known_values
    %w(lean_mass fat_mass fat_percent_value bmi).each do |measurement|
      self.try("calculate_#{measurement}")
    end
  end

  def calculate_bmi
    if user && user.height
      self.bmi = value / ( Unit.new(user.height, :centimeters).to_unit(:meters) ** 2 )
    end
  end

  def calculate_lean_mass
    calculate_missing_value :lean_mass, fat_mass, fat_percent
  end

  def calculate_fat_mass
    calculate_missing_value :fat_mass, lean_mass, fat_percent
  end

  def calculate_fat_percent_value
    self.fat_percent ||= if lean_mass
      (value - lean_mass) / value * 100
    elsif fat_mass
      (fat_mass / value) * 100
    end
  end

  def self.update_bmi_for_user id
    User.find(id).weights.each do |weight|
      weight.save #executes callbacks that update the bmi
    end
  end

  def self.interpolate(weights=[])
    return unless weights.present?

    possible_dates, start_date, end_date = [], weights.first.date.at_beginning_of_day, weights.last.date.at_beginning_of_day

    while(start_date < end_date - 1.day) do
      possible_dates.push start_date.to_f
      start_date += 1.day
    end

    actual_dates = weights.group_by { |w| w.date.at_beginning_of_day.to_f }

    need_to_be_interpolated_dates = possible_dates - actual_dates.keys

    bucketizer = Interpolate::Points.new(Hash[actual_dates.map { |k,v| [k, v.first.value] }])

    interpolated_data = need_to_be_interpolated_dates.map do |value|
      puts value
      bucket = bucketizer.at(value)
    end

    [need_to_be_interpolated_dates, interpolated_data].transpose.map{|w| Weight.new(date: Time.at(w[0]).to_datetime, value: w[1])}
  end

  protected

  def calculate_missing_value missing, k, j
    self[missing] ||= if k
      value - k
    elsif j
      value - (value * (j / 100))
    end
  end

end
