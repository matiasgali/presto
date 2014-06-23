###
 * jQuery Presto Plugin v1.0.0.alpha
 * http://matiasgagliano.github.com/presto/
 *
 * Copyright 2014, Matías Gagliano.
 * Dual licensed under the MIT or GPLv3 licenses.
 * http://opensource.org/licenses/MIT
 * http://opensource.org/licenses/GPL-3.0
 *
###
"use strict"

# ______________________________
#
#           Constants
# ______________________________
#
$ = jQuery
pluginName = 'presto'
scope = 'presto'

# Errors list (number and default message)
errors =
  1: { n: 1, message: "The image couldn't be displayed." }
  2: { n: 2, message: "The image couldn't be uploaded." }
  3: { n: 3, message: "Image format not supported." }

# Default options
defaults =
  # _____ Options _____
  #
  # Whether to automatically revoke Blob URLs or not.
  # If a URL is revoked it frees the Blob and allows it to be garbage collected.
  # If you need to work with the src of the image set this to false.
  # To revoke manually, call revokeObjectURL with the image's src.
  revokeUrls: true

  # jQuery AJAX settings for iframe transport (jquery.bifrost.js).
  # http://matiasgagliano.github.com/bifrost/
  #
  # Notice: fileInputs and dataType settings are automatically set to
  # be the target file input and 'iframe json' respectively.
  iframe: false
    # url: '/somewhere/over/the/rainbow.html'
    # type: 'POST'
    # data: {}

  # _____ Callbacks _____
  #
  before: null
    # Before everything, right after the input's value changes.
    # Everything is aborted if this explicitly returns false.
    # @param input The file input element
  beforeEach: null
    # Before handling or uploading each file.
    # The current file is skipped if this explicitly returns false.
    # @param file  Current file if supported or the value of the file input.
    # @param input The file input element
  success: null
    # Success callback for each file (after the image has been loaded).
    # @param img   The created img element
    # @param data  Current file if supported or iframe transport response
    # @param input The file input element
  error: null
    # Error callback for each file.
    # @param error One of the error objects from the errors list above.
    # @param input The file input element
  always: null
    # Do always, after success or error, for each file.
    # @param input The file input element
  after: null
    # After every file has been processed.
    # @param input The file input element

# Avoid errors if there's no console
console = window.console || { log: -> }



# ______________________________
#
#             Helpers
# ______________________________
#
isFileInput = (input) ->
  input.prop('tagName') is 'INPUT' and input.attr('type') is 'file' ||
  !!console.log 'Presto error: Not a file input.'

createBlobURL = (window.URL && URL.createObjectURL.bind(URL)) ||
                (window.webkitURL && webkitURL.createObjectURL.bind(webkitURL)) ||
                window.createObjectURL

# Release the URL to allow the Blob to be garbage collected.
revokeBlobURL = (window.URL && URL.revokeObjectURL.bind(URL)) ||
                (window.webkitURL && webkitURL.revokeObjectURL.bind(webkitURL)) ||
                window.revokeObjectURL

# Cache
canCreateURL = $.type(createBlobURL) is 'function'
canReadFile  = !!window.FileReader



# ______________________________
#
#      And Presto... magic!
# ______________________________
#
class Presto
  constructor: (input, options) ->
    @input = input = $(input)
    return unless isFileInput(input)

    # Build options
    # The data attribute overrides options, and options override defaults.
    # E.g. data-presto='{ "iframe": false }'
    @op = $.extend true, {}, defaults, options, input.data(pluginName)

    # Check callbacks
    for func in ['before', 'beforeEach', 'success', 'error', 'always', 'after']
      @op[func] = null unless $.type(@op[func]) is 'function'

    # Iframe settings
    @op.iframe = false unless @op.iframe and @op.iframe.url
    $.extend @op.iframe, {dataType: 'iframe json', fileInputs: @input} if @op.iframe

    # Choose the best method to display the images
    @_castImgSpell = @_chooseSpell()
    return unless @_castImgSpell

    # Enable and start
    @enabled = true
    @input.on "change.#{scope}", @_doMagic


  # _____ Private _____
  #
  _chooseSpell: ->
    if canCreateURL     then @_createURL
    else if canReadFile then @_readFile
    else if @op.iframe  then @_iframeTransport
    else console.log('Presto error: No method to display images.') || null

  _doMagic: =>
    return unless @enabled
    return if @op.before and @op.before(@input) is false
    total = if @input.val() then 1 else 0
    total = if @input[0].files? then @input[0].files.length
    return if total is 0
    @total = total
    @count = 0
    @_castImgSpell()

  _summonImg: (src, data) ->
    img = $('<img>')
    img.on 'load', =>
      revokeBlobURL(src) if canCreateURL and @op.revokeURL
      @_success(img, data)
    img.on 'error', =>
      revokeBlobURL(src) if canCreateURL and @op.revokeURL
      @_error 3
    img.attr 'src', src

  _success: (img, data) ->
    @count++
    @op.success img, data, @input if @op.success
    @op.always @input if @op.always
    @op.after @input if @count == @total and @op.after

  _error: (number) ->
    @count++
    @op.error errors[number], @input if @op.error
    @op.always @input if @op.always
    @op.after @input if @count == @total and @op.after


  #_____ Spells ____
  #
  # Blob URL
  _createURL: ->
    for file in @input[0].files
      continue if @op.beforeEach and @op.beforeEach(file, @input) is false
      @_summonImg createBlobURL(file), file

  # File Reader
  _readFile: ->
    for file in @input[0].files
      continue if @op.beforeEach and @op.beforeEach(file, @input) is false
      @_read(file)

  _read: (file) ->
    reader = new FileReader()
    reader.onload  = => @_summonImg reader.result, file
    reader.onerror = => @_error 1
    reader.readAsDataURL file

  # Iframe transport
  _iframeTransport: ->
    return if @op.beforeEach and @op.beforeEach(@input.val(), @input) is false
    request = $.ajax @op.iframe
    request.done (data) => @_summonImg(data.src, data)
    request.fail => @_error 2


  # _____ Public (the API) _____
  #
  enable: -> @enabled = true
  disable: -> @enabled = false
  remove: ->
    @input.off "change.#{scope}", @_doMagic
    @input.removeData(pluginName + 'Instance')


# ______________________________
#
#           The Plugin
# ______________________________
#
$.fn[pluginName] = (options) ->
  # Plug it! Lightweight plugin wrapper around the constructor.
  if typeof options isnt 'string'
    @each ->
      # Prevent multiple instantiation
      unless $.data(@, pluginName + 'Instance')
        # Presto's instance
        presto = new Presto(@, options)
        $.data(@, pluginName + 'Instance', presto)

  # Plugin's API
  else if options in ['enable', 'disable', 'remove']
    @each ->
      presto = $.data(@, pluginName + 'Instance')
      presto[options]() if presto?
