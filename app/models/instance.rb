class Instance < ApplicationRecord
  validates :name, presence: true, uniqueness: true
end
