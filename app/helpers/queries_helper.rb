#-- encoding: UTF-8
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

module QueriesHelper
  def operators_for_select(filter_type)
    Queries::BaseFilter.operators_by_filter_type[filter_type].map { |o| [l(Queries::BaseFilter.operators[o]), o] }
  end

  def entries_for_filter_select_sorted(query)
    [['', '']] +
      query.available_filters
           .reject { |filter| query.has_filter?(filter.name) }
           .map { |filter| [filter.human_name, filter.name] }
           .sort_by { |el| ActiveSupport::Inflector.transliterate(el[0]).downcase }
  end

  def column_locale(column)
    column.is_a?(QueryCustomFieldColumn) ? column.custom_field.name_locale : nil
  end

  def add_filter_from_params(query, filters: params)
    query.filters = []
    query.add_filters(
      fields_from_params(query, filters),
      operators_from_params(query, filters),
      values_from_params(query, filters)
    )
  end

  # Retrieve query from session or build a new query
  def retrieve_query
    if params[:query_id].present?
      cond = 'project_id IS NULL'
      cond << " OR project_id = #{@project.id}" if @project
      @query = Query.where(cond).find(params[:query_id])
      @query.project = @project
      add_filter_from_params(@query) if params[:accept_empty_query_fields]
      session[:query] = { id: @query.id, project_id: @query.project_id }
      sort_clear
    else
      if api_request? || params[:set_filter] || session[:query].nil? || session[:query][:project_id] != (@project ? @project.id : nil)
        # Give it a name, required to be valid
        @query = Query.new(name: '_')
        @query.project = @project
        if params[:fields] || params[:f]
          add_filter_from_params(@query)
        else
          @query.available_filters.map(&:name).each do |field|
            @query.add_short_filter(field, params[field]) if params[field]
          end
        end

        @query.group_by = group_by_from_params params
        @query.display_sums = params[:display_sums].present? && params[:display_sums] == 'true'
        @query.column_names = column_names_from_params params
        session[:query] = {
          project_id: @query.project_id,
          filters: Queries::FilterSerializer.dump(@query.filters),
          group_by: @query.group_by,
          display_sums: @query.display_sums,
          column_names: @query.column_names
        }
      else
        @query = Query.find_by(id: session[:query][:id]) if session[:query][:id]
        @query ||= Query.new(name: '_',
                             project: @project,
                             filters: Queries::FilterSerializer.load(session[:query][:filters]),
                             group_by: session[:query][:group_by],
                             display_sums: session[:query][:display_sums],
                             column_names: session[:query][:column_names])
        @query.project = @project
      end
    end

    @query
  end

  ##
  # Reads column names from the request parameters and converts them
  # from the frontend names to names recognized by the backend.
  # Examples:
  #   * assigned => assigned_to
  #   * customField1 => cf_1
  #
  # @param params [Hash] Request parameters
  # @return [Array] The column names read from the parameters or nil if none were given.
  def column_names_from_params(params)
    names = params[:c] || (params[:query] && params[:query][:column_names])

    if names
      context = WorkPackage.new

      names.map { |name| converter.to_ar_name name, context: context }
    end
  end

  def visible_queries
    unless @visible_queries
      # User can see public queries and his own queries
      visible = ARCondition.new(['is_public = ? OR user_id = ?', true, (User.current.logged? ? User.current.id : 0)])
      # Project specific queries and global queries
      visible << (@project.nil? ? ['project_id IS NULL'] : ['project_id = ?', @project.id])
      @visible_queries = Query.where(visible.conditions)
                         .order('name ASC')
                         .select(:id, :name, :is_public, :project_id)
    end
    @visible_queries
  end

  module_function

  def group_by_from_params(params)
    params[:group_by] || params[:groupBy] || params[:g]
  end

  def fields_from_params(query, params)
    fix_field_array(query, params[:fields] || params[:f]).compact
  end

  def operators_from_params(query, params)
    fix_field_hash(query, params[:operators] || params[:op])
  end

  def values_from_params(query, params)
    fix_field_hash(query, params[:values] || params[:v])
  end

  def fix_field_hash(query, field_hash)
    return nil if field_hash.nil?

    names = field_hash.keys
    entries = names
              .zip(fix_field_array(query, names))
              .select { |_name, field| field.present? }
              .map { |name, field| [field, field_hash[name]] }

    Hash[entries]
  end

  ##
  # Maps given field names coming from the frontend to the actual names
  # as expected by the query. This works slightly different to what happens
  # in #column_names_from_params. For instance while they column name is
  # :type the expected field name is :type_id.
  #
  # Examples:
  #   * status => status_id
  #   * progresssDone => done_ratio
  #   * assigned => assigned_to
  #   * customField1 => cf_1
  #
  # @param query [Query] Query for which to get the correct field names.
  # @param field_names [Array] Field names as read from the params.
  # @return [Array] Returns a list of fixed field names. The list may contain nil values
  #                 for fields which could not be found.
  def fix_field_array(query, field_names)
    return [] if field_names.nil?

    # memoize to reduce overhead of WorkPackage.new
    @fix_field_array_wp ||= WorkPackage.new
    available_keys = query.available_filters.map(&:name)

    field_names
      .map { |name| converter.to_ar_name name, context: @fix_field_array_wp, refer_to_ids: true }
      .map { |name| available_keys.find { |k| name =~ /#{k}(s|_id)?$/ } }
  end

  def converter
    API::Utilities::PropertyNameConverter
  end
end
