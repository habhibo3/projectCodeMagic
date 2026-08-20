allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
    
    // Inject namespace dynamically if a library/plugin doesn't specify one (fixes build failure for older packages like flutter_screen_recording)
    val configureNamespace = {
        val android = project.extensions.findByName("android")
        if (android != null) {
            try {
                val getNamespace = android.javaClass.getMethod("getNamespace")
                val namespace = getNamespace.invoke(android) as? String
                if (namespace.isNullOrEmpty()) {
                    val setNamespace = android.javaClass.getMethod("setNamespace", String::class.java)
                    
                    var packageId = ""
                    val manifestFile = project.file("src/main/AndroidManifest.xml")
                    if (manifestFile.exists()) {
                        val content = manifestFile.readText()
                        val match = Regex("""package\s*=\s*"([^"]+)"""").find(content)
                        if (match != null) {
                            packageId = match.groupValues[1]
                        }
                    }
                    if (packageId.isEmpty()) {
                        packageId = "com.example.${project.name.replace("-", ".").replace("_", ".")}"
                    }
                    
                    setNamespace.invoke(android, packageId)
                }
            } catch (e: Exception) {
                // Ignore if method doesn't exist
            }
        }
    }

    if (project.state.executed) {
        configureNamespace()
    } else {
        project.afterEvaluate {
            configureNamespace()
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
