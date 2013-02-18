sass = require 'node-sass'
coffeelint = require 'coffeelint'
colorize = require "colorize"
events = require "events"

Paths = require "./paths"

defaultConfig = {}

registerDefaultTasks = (grunt)->
  grunt.registerTask 'steroids-default', [
    'steroids-clean-dist',
    'steroids-build-controllers',
    'steroids-build-models',
    'steroids-build-statics',
    'steroids-compile-coffeescript-files',
    'steroids-compile-sass-files',
    'steroids-compile-models'
    'steroids-compile-views',
  ]

  # -------------------------------------------
  # CLEAN TASKS

  grunt.registerTask 'steroids-clean-dist', 'Removes dist/ recursively and creates it again ', ->
    wrench.rmdirSyncRecursive Paths.application.distDir, true
    grunt.file.mkdir Paths.application.distDir

  # -------------------------------------------
  # BUILD TASKS

  copyFilesSyncRecursive = (options)->
    grunt.verbose.writeln "Copying files from #{options.sourcePath} to #{options.destinationDir} using #{options.relativeDir} as basedir"

    for filePath in grunt.file.expandFiles options.sourcePath
      grunt.verbose.writeln "Copying file #{filePath}"

      relativePath = path.relative options.relativeDir, filePath
      destinationPath = path.join options.destinationDir, relativePath

      grunt.verbose.writeln "Copying file #{filePath} to #{destinationPath}"

      grunt.file.copy filePath, destinationPath

  grunt.registerTask 'steroids-build-controllers', "Build controllers", ->
    copyFilesSyncRecursive {
      sourcePath: Paths.application.sources.controllers
      destinationDir: Paths.application.distDir
      relativeDir: Paths.application.appDir
    }

  grunt.registerTask 'steroids-build-models', "Build models", ->
    copyFilesSyncRecursive {
      sourcePath: Paths.application.sources.models
      destinationDir: Paths.application.distDir
      relativeDir: Paths.application.appDir
    }

  grunt.registerTask 'steroids-build-statics', "Build static files", ->
    copyFilesSyncRecursive {
      sourcePath: Paths.application.sources.statics
      destinationDir: Paths.application.distDir
      relativeDir: Paths.application.sources.staticDir
    }

  # -------------------------------------------
  # COMPILE TASKS

  grunt.registerTask 'steroids-compile-coffeescript-files', "Compile built coffeescript files", ->
    grunt.verbose.writeln "Compiling coffeescripts #{Paths.application.compiles.coffeescripts}"
    coffeeFiles = grunt.file.expandFiles Paths.application.compiles.coffeescripts

    for filePath in coffeeFiles
      grunt.verbose.writeln "Compiling coffeescript at #{filePath}"
      coffeeFile = new CoffeeScriptFile(filePath: filePath)

      coffeeFile.on "compiled", =>
        fs.unlinkSync filePath

      coffeeFile.compile()

  grunt.registerTask 'steroids-compile-sass-files', "Compile build sass files", ->
    sassFiles = grunt.file.expandFiles Paths.application.compiles.sassfiles
    scssFiles = grunt.file.expandFiles Paths.application.compiles.scssfiles

    for filePath in sassFiles.concat(scssFiles)
      grunt.verbose.writeln "Compiling sass file at #{filePath}"
      sassFile = new SassFile(filePath: filePath)

      sassFile.on "compiled", =>
        fs.unlinkSync filePath
        @async()

      sassFile.compile()

  grunt.registerTask 'steroids-compile-models', "Compile models", ->
    javascripts = []
    sourceFiles = grunt.file.expand Paths.application.compiles.models

    for filePath in sourceFiles
      grunt.verbose.writeln "Compiling model file at #{filePath}"
      javascripts.push grunt.file.read(filePath, "utf8").toString()
      fs.unlinkSync filePath

    grunt.file.write Paths.application.compileProducts.models, javascripts.join("\n\n")

  class CoffeeScriptFile extends events.EventEmitter
    constructor: (@options)->
      @sourcePath = @options.filePath
      @destinationPath = @sourcePath.replace path.extname(@sourcePath), ".js"
      @contents = grunt.file.read(@sourcePath, "utf8").toString()

    compile: ()->
      @checkWithLint()

      if @lintErrors.length > 0
        @reportLintErrors()
        return false

      try
        compiledSource = coffee.compile(@contents)
        grunt.file.write @destinationPath, compiledSource
        @emit "compiled"
      catch err
        grunt.warn err

    checkWithLint: ->
      @lintErrors = coffeelint.lint @contents,
        max_line_length:
          level: "ignore"
        no_backticks:
          level: "ignore"

    reportLintErrors: ->
      text = "#red[#{@lintErrors.length} errors in #underline[#{@sourcePath}]]\n\n"

      for error in @lintErrors
        text += "#red[#{path.basename(@sourcePath)}:#{error.lineNumber}] > #yellow[#{error.message if error.message?}] #green[#{'('+error.context+')' if error.context?}]\n\n"
        if error.line?
          text += "\n#{error.line}\n\n\n"

      grunt.warn colorize.ansify text


  class SassFile extends events.EventEmitter
    constructor: (@options)->
      @sourcePath = @options.filePath
      @destinationPath = @sourcePath.replace path.extname(@sourcePath), ".css"
      @contents = grunt.file.read(@sourcePath, "utf8").toString()

    compile: ()->
      sassCallback = (err, css)=>
        if err
          text = "#red[Errors in #underline[#{@sourcePath}]]\n\n"
          text += "#red[#{path.basename(@sourcePath)}]#yellow[#{err}]"
          grunt.warn colorize.ansify(text)
        else
          grunt.file.write @destinationPath, css

        @emit "compiled"

      sass.render @contents, sassCallback,
        output_style: "compressed"


  grunt.registerTask 'steroids-compile-views', "Compile views", ->
    projectDirectory          = Paths.applicationDir

    buildDirectory            = path.join projectDirectory, "dist"
    buildViewsDirectory       = path.join buildDirectory, "views"
    buildModelsDirectory      = path.join buildDirectory, "models"
    buildcontrollersDirectory = path.join buildDirectory, "controllers"
    buildStylesheetsDirectory = path.join buildDirectory, "stylesheets"

    appDirectory              = path.join projectDirectory, "app"
    appViewsDirectory         = path.join appDirectory, "views"
    appModelsDirectory        = path.join appDirectory, "models"
    appControllersDirectory   = path.join appDirectory, "controllers"
    appLayoutsDirectory       = path.join appDirectory, "views", "layouts"

    vendorDirectory           = path.join projectDirectory, "vendor"
    wwwDirectory              = path.join projectDirectory, "www"

    viewDirectories = []

    # get each view folder (except layout)
    for dirPath in grunt.file.expandDirs(path.join(appViewsDirectory, "*"))
      basePath = path.basename(dirPath)
      unless basePath is "layouts" + path.sep or basePath is "layouts"
        viewDirectories.push dirPath
        grunt.file.mkdir path.join(buildViewsDirectory, path.basename(dirPath))

    for viewDir in viewDirectories
      # resolve layout file for these views
      layoutFileName = "";

      # Some machines report folder/ as basename while others do not
      viewBasename = path.basename viewDir
      unless viewBasename.indexOf(path.sep) is -1
        viewBasename = viewBasename.replace path.sep, ""

      layoutFileName = "#{viewBasename}.html"

      layoutFilePath = path.join appLayoutsDirectory, layoutFileName

      unless fs.existsSync(layoutFilePath)
        layoutFilePath = path.join appLayoutsDirectory, "application.html"

      applicationLayoutFile = grunt.file.read layoutFilePath, "utf8"

      for filePathPart in grunt.file.expand(path.join(viewDir, "**", "*"))
        filePath = path.resolve filePathPart
        buildFilePath = path.resolve filePathPart.replace("app"+path.sep, "dist"+path.sep)

        # skip "partial" files that begin with underscore
        if /^_/.test path.basename(filePath)
          yieldedFile = grunt.file.read(filePath, "utf8")
        else
          controllerName = path.basename(viewDir).replace(path.sep, "")
          unless fs.existsSync path.join(buildcontrollersDirectory, "#{controllerName}.js")
            # project haz legacy
            text = "#red[Deprecation Warning:] controller filenames should no longer include Controller. Rename #underline[#{path.join("app", "controllers", "#{controllerName}Controller.{coffee|js}")}] to #underline[#{path.join("app", "controllers", "#{controllerName}.{coffee|js}")}]"
            grunt.log.writeln colorize.ansify(text)

            # work around legacy and continue
            controllerName += "Controller"

          yieldObj =
            view: grunt.file.read(filePath, "utf8")
            controller: controllerName

          # put layout+yields together
          yieldedFile = grunt.utils._.template(
            applicationLayoutFile.toString()
          )({ yield: yieldObj })

        # write the file
        grunt.file.mkdir path.dirname(buildFilePath)
        grunt.file.write buildFilePath, yieldedFile


module.exports =
  registerDefaultTasks: registerDefaultTasks
  defaultConfig: defaultConfig
