# Copyright 2010-2015 RethinkDB, all rights reserved.

r = require('rethinkdb')
h = require('virtual-dom/h')
vdom = require('../vdom_util.coffee')
util = require('../util.coffee')

app = require('../app.coffee')
system_db = app.system_db

systable = (name) => r.db(system_db).table(name)

class ServersModel extends Backbone.Model
    @query: (server_status=systable('server_status'), \
             table_config=systable('table_config')) ->
        r.do(
            # All connected servers
            server_status('name').coerceTo('array')
            # All servers assigned to tables
            table_config
                .concatMap((row)->row('shards').default([]))
                .concatMap((row)->row('replicas'))
                .distinct()
            (connected_servers, assigned_servers) ->
                servers_connected:
                    connected_servers.count()
                servers_unassigned:
                    connected_servers.setDifference(assigned_servers)
                servers_missing:
                    assigned_servers.setDifference(connected_servers)
                unknown_missing:
                    table_config.filter((row)->
                        row.hasFields('shards').not())('name').isEmpty().not()
        )

    defaults:
        servers_connected: 0
        servers_unassigned: []
        servers_missing: []
        unknown_missing: false


class ServersView extends vdom.VirtualDomView
    render_vdom: ->
        model = @model.toJSON()
        num_servers_missing = model.servers_missing.length
        unknown_missing = model.unknown_missing
        servers_missing =
            if unknown_missing and num_servers_missing > 0
                "#{num_servers_missing}+"
            else if unknown_missing and num_servers_missing <= 0
                "1+"
            else
                "#{num_servers_missing}"
        problems_exist = unknown_missing or num_servers_missing != 0
        elements = [
            "#{model.servers_connected} servers connected"
            "#{model.servers_unassigned.length} servers unassigned"
            "#{servers_missing} servers missing"
        ]
        render_panel("Servers", problems_exist, elements)


class TablesModel extends Backbone.Model
    @query: (table_status=systable('table_status')) ->
        d =
            all_replicas_ready: false
            ready_for_outdated_reads: false
            ready_for_writes: false
            ready_for_reads: false
        tables_ready: table_status.count((row) ->
            row('status').default(d)('all_replicas_ready'))
        tables_reduced: table_status.count((row) ->
            row('status').default(d)('all_replicas_ready').not().and(
                row('status').default(d)('ready_for_outdated_reads')))
        tables_unavailable: table_status.count((row) ->
            row('status').default(d)('ready_for_outdated_reads').not())

    defaults:
        tables_ready: 0
        tables_reduced: 0
        tables_unavailable: 0


class TablesView extends vdom.VirtualDomView
    render_vdom: ->
        model = @model.toJSON()
        problems_exist = model.tables_reduced + model.tables_unavailable > 0
        elements = [
            ["#{model.tables_ready} ",
              util.pluralize_noun("table", model.tables_ready),
              " ready"]
            ["#{model.tables_reduced} ",
              util.pluralize_noun("table", model.tables_reduced),
              " reduced"]
            ["#{model.tables_unavailable} ",
              util.pluralize_noun("table", model.tables_unavailable),
              " unavailable"]
        ]
        render_panel("Tables", problems_exist, elements)

# class IndexesModel extends Backbone.Model
#     @query: ''



render_panel = (panel_name, problems_exist, elements) =>
    problems_class = if problems_exist
        "problems-detected"
    else
        "no-problems-detected"
    h "div.dashboard-panel.servers", [
        h "div.status.#{problems_class}", [
            h "h3", panel_name
            h "ul", elements.map((element) ->
                h "li", element)
        ]
    ]

exports.ServersView = ServersView
exports.ServersModel = ServersModel
exports.TablesView = TablesView
exports.TablesModel = TablesModel
# exports.IndexesView = IndexesView
# exports.IndexesModel = IndexesModel
# exports.ResourcesView = ResourcesView
# exports.ResourcesModel = ResourcesModel
