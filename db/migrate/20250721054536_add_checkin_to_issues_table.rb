class AddCheckinToIssuesTable < ActiveRecord::Migration[7.2]
  def change
    add_column :issues, :check_in_time, :string, default: nil
    add_column :issues, :check_out_time, :string, default: nil
  end
end
