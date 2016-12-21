#-- copyright
# OpenProject Costs Plugin
#
# Copyright (C) 2009 - 2014 the OpenProject Foundation (OPF)
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# version 3.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#++

require 'spec_helper'

describe WorkPackage, 'cost eager loading', type: :model do
  let(:project) do
    work_package.project
  end
  let(:role) do
    FactoryGirl.create(:role,
                       permissions: [:view_work_packages,
                                     :view_cost_entries,
                                     :view_cost_rates,
                                     :view_time_entries,
                                     :log_time,
                                     :log_costs,
                                     :view_hourly_rates])
  end
  let(:user) do
    FactoryGirl.create(:user,
                       member_in_project: project,
                       member_through_role: role)
  end

  let(:cost_type) do
    FactoryGirl.create(:cost_type)
  end
  let(:work_package) do
    FactoryGirl.create(:work_package)
  end
  let(:cost_entry1) do
    FactoryGirl.create(:cost_entry,
                       cost_type: cost_type,
                       user: user,
                       work_package: work_package,
                       project: project)
  end
  let(:cost_entry2) do
    FactoryGirl.create(:cost_entry,
                       cost_type: cost_type,
                       user: user,
                       work_package: work_package,
                       project: project)

  end
  let(:time_entry1) do
    FactoryGirl.create(:time_entry,
                       user: user,
                       project: project,
                       work_package: work_package)
  end
  let(:time_entry2) do
    FactoryGirl.create(:time_entry,
                       user: user,
                       project: project,
                       work_package: work_package)
  end
  let(:user_rates) do
    FactoryGirl.create(:hourly_rate,
                       user: user,
                       project: project)
  end
  let(:cost_rate) do
    FactoryGirl.create(:cost_rate,
                       cost_type: cost_type)
  end

  context "combining core's and cost's eager loading" do
    let(:scope) do

      scope = WorkPackage
              .include_spent_hours(user)
              .where(id: [work_package.id])

      OpenProject::Costs::Engine::EagerLoadedCosts.join_costs(scope)
    end

    before do
      allow(User)
        .to receive(:current)
        .and_return(user)

      user_rates
      project.reload
      cost_rate
      cost_entry1
      cost_entry2
      time_entry1
      time_entry2
    end

    subject { scope.first }

    it 'correctly calculates spent time' do
      expect(scope.to_a.first.hours).to eql time_entry1.hours + time_entry2.hours
    end

    it 'correctly calculates labor costs' do
      expect(scope.first.labor_costs).to eql (user_rates.rate * (time_entry1.hours + time_entry2.hours)).to_f
    end

    it 'correctly calculates material costs' do
      expect(scope.first.material_costs).to eql (cost_entry1.costs + cost_entry2.costs).to_f
    end
  end
end
