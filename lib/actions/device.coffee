###
Copyright 2016 Resin.io

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
###

commandOptions = require('./command-options')

exports.list =
	signature: 'devices'
	description: 'list all devices'
	help: '''
		Use this command to list all devices that belong to you.

		You can filter the devices by application by using the `--application` option.

		Examples:

			$ resin devices
			$ resin devices --application MyApp
			$ resin devices --app MyApp
			$ resin devices -a MyApp
	'''
	options: [ commandOptions.optionalApplication ]
	permission: 'user'
	primary: true
	action: (params, options, done) ->
		Promise = require('bluebird')
		_ = require('lodash')
		resin = require('resin-sdk')
		visuals = require('resin-cli-visuals')

		Promise.try ->
			if options.application?
				return resin.models.device.getAllByApplication(options.application)
			return resin.models.device.getAll()

		.tap (devices) ->
			devices = _.map devices, (device) ->
				device.uuid = device.uuid.slice(0, 7)
				return device

			console.log visuals.table.horizontal devices, [
				'id'
				'uuid'
				'name'
				'device_type'
				'application_name'
				'status'
			]
		.nodeify(done)

exports.info =
	signature: 'device <uuid>'
	description: 'list a single device'
	help: '''
		Use this command to show information about a single device.

		Examples:

			$ resin device 7cf02a6
	'''
	permission: 'user'
	primary: true
	action: (params, options, done) ->
		resin = require('resin-sdk')
		visuals = require('resin-cli-visuals')
		events = require('resin-cli-events')

		resin.models.device.get(params.uuid).then (device) ->

			# TODO: We should outsource this logic and probably
			# other last_seen edge cases to either Resin CLI Visuals
			# or have it parsed appropriately in the SDK.
			device.last_seen ?= 'Not seen'

			console.log visuals.table.vertical device, [
				"$#{device.name}$"
				'id'
				'device_type'
				'is_online'
				'ip_address'
				'application_name'
				'status'
				'last_seen'
				'uuid'
				'commit'
				'supervisor_version'
				'is_web_accessible'
				'note'
			]
			events.send('device.open', device: device.uuid)
		.nodeify(done)

exports.register =
	signature: 'device register <application>'
	description: 'register a device'
	help: '''
		Use this command to register a device to an application.

		Examples:

			$ resin device register MyApp
	'''
	permission: 'user'
	options: [
		signature: 'uuid'
		description: 'custom uuid'
		parameter: 'uuid'
		alias: 'u'
	]
	action: (params, options, done) ->
		Promise = require('bluebird')
		resin = require('resin-sdk')

		resin.models.application.get(params.application).then (application) ->

			Promise.try ->
				return options.uuid or resin.models.device.generateUUID()
			.then (uuid) ->
				console.info("Registering to #{application.app_name}: #{uuid}")
				return resin.models.device.register(application.app_name, uuid)
		.get('uuid')
		.nodeify(done)

exports.remove =
	signature: 'device rm <uuid>'
	description: 'remove a device'
	help: '''
		Use this command to remove a device from resin.io.

		Notice this command asks for confirmation interactively.
		You can avoid this by passing the `--yes` boolean option.

		Examples:

			$ resin device rm 7cf02a6
			$ resin device rm 7cf02a6 --yes
	'''
	options: [ commandOptions.yes ]
	permission: 'user'
	action: (params, options, done) ->
		resin = require('resin-sdk')
		events = require('resin-cli-events')
		patterns = require('../utils/patterns')

		patterns.confirm(options.yes, 'Are you sure you want to delete the device?').then ->
			resin.models.device.remove(params.uuid)
		.tap ->
			events.send('device.delete', device: params.uuid)
		.nodeify(done)

exports.identify =
	signature: 'device identify <uuid>'
	description: 'identify a device with a UUID'
	help: '''
		Use this command to identify a device.

		In the Raspberry Pi, the ACT led is blinked several times.

		Examples:

			$ resin device identify 23c73a1
	'''
	permission: 'user'
	action: (params, options, done) ->
		resin = require('resin-sdk')
		resin.models.device.identify(params.uuid).nodeify(done)

exports.rename =
	signature: 'device rename <uuid> [newName]'
	description: 'rename a resin device'
	help: '''
		Use this command to rename a device.

		If you omit the name, you'll get asked for it interactively.

		Examples:

			$ resin device rename 7cf02a6
			$ resin device rename 7cf02a6 MyPi
	'''
	permission: 'user'
	action: (params, options, done) ->
		Promise = require('bluebird')
		_ = require('lodash')
		resin = require('resin-sdk')
		events = require('resin-cli-events')
		form = require('resin-cli-form')

		Promise.try ->
			return params.newName if not _.isEmpty(params.newName)

			form.ask
				message: 'How do you want to name this device?'
				type: 'input'

		.then(_.partial(resin.models.device.rename, params.uuid))
		.tap ->
			events.send('device.rename', device: params.uuid)
		.nodeify(done)

exports.move =
	signature: 'device move <uuid>'
	description: 'move a device to another application'
	help: '''
		Use this command to move a device to another application you own.

		If you omit the application, you'll get asked for it interactively.

		Examples:

			$ resin device move 7cf02a6
			$ resin device move 7cf02a6 --application MyNewApp
	'''
	permission: 'user'
	options: [ commandOptions.optionalApplication ]
	action: (params, options, done) ->
		resin = require('resin-sdk')
		_ = require('lodash')
		patterns = require('../utils/patterns')

		resin.models.device.get(params.uuid).then (device) ->
			return options.application or patterns.selectApplication (application) ->
				return _.all [
					application.device_type is device.device_type
					device.application_name isnt application.app_name
				]
		.tap (application) ->
			return resin.models.device.move(params.uuid, application)
		.then (application) ->
			console.info("#{params.uuid} was moved to #{application}")
		.nodeify(done)

exports.init =
	signature: 'device init'
	description: 'initialise a device with resin os'
	help: '''
		Use this command to download the OS image of a certain application and write it to an SD Card.

		Notice this command may ask for confirmation interactively.
		You can avoid this by passing the `--yes` boolean option.

		Examples:

			$ resin device init
			$ resin device init --application MyApp
	'''
	options: [
		commandOptions.optionalApplication
		commandOptions.yes
		{
			signature: 'advanced'
			description: 'enable advanced configuration'
			boolean: true
			alias: 'v'
		}
	]
	permission: 'user'
	action: (params, options, done) ->
		Promise = require('bluebird')
		capitano = Promise.promisifyAll(require('capitano'))
		rimraf = Promise.promisify(require('rimraf'))
		tmp = Promise.promisifyAll(require('tmp'))
		tmp.setGracefulCleanup()

		resin = require('resin-sdk')
		helpers = require('../utils/helpers')
		patterns = require('../utils/patterns')

		Promise.try ->
			return options.application if options.application?
			return patterns.selectApplication()
		.then(resin.models.application.get)
		.then (application) ->

			download = ->
				tmp.tmpNameAsync().then (temporalPath) ->
					capitano.runAsync("os download #{application.device_type} --output #{temporalPath}")
				.disposer (temporalPath) ->
					return rimraf(temporalPath)

			Promise.using download(), (temporalPath) ->
				capitano.runAsync("device register #{application.app_name}")
					.then(resin.models.device.get)
					.tap (device) ->
						configure = "os configure #{temporalPath} #{device.uuid}"
						configure += ' --advanced' if options.advanced
						capitano.runAsync(configure).then ->
							message = '''
								Initializing a device requires administration permissions
								given that we need to access raw devices directly.

							'''

							helpers.sudo([ 'os', 'initialize', temporalPath, '--type', application.device_type ], message)

						# Make sure the device resource is removed if there is an
						# error when configuring or initializing a device image
						.catch (error) ->
							resin.models.device.remove(device.uuid).finally ->
								throw error
			.then (device) ->
				console.log('Done')
				return device.uuid

		.nodeify(done)
