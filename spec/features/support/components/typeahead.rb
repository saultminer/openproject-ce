#-- copyright
# OpenProject is a project management system.
# Copyright (C) 2012-2015 the OpenProject Foundation (OPF)
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# OpenProject is a fork of ChiliProject, which is a fork of Redmine. The copyright follows:
# Copyright (C) 2006-2013 Jean-Philippe Lang
# Copyright (C) 2010-2013 the ChiliProject Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# See doc/COPYRIGHT.rdoc for more details.
#++

shared_context 'typeahead helpers' do
  def search_typeahead(element, query:)
    # Open the element
    element.click
    # Insert the text to find
    element.set(query)

    ##
    # Find the dropdown by reference
    element['aria-owns']
  end

  def select_typeahead(element, query:, select_text: nil)
    target_dropdown = search_typeahead(element, query: query)

    ##
    # If a specific select_text is given, use that to locate the match,
    # otherwise use the query
    text = select_text.presence || query

    # click the element to select it
    page.find("##{target_dropdown} .uib-typeahead-match", text: text).click
  end
end
