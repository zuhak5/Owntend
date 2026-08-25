allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

// Gradle cannot relativize generated plugin sources across Windows drive
// roots. Keep app/workspace outputs in the standard Flutter build directory,
// but place external pub-cache plugin intermediates on the same drive as their
// source. This avoids modifying the pub cache and keeps the workaround scoped
// to disposable build output.
val workspaceDriveRoot = rootProject.projectDir.toPath().root
val externalPluginBuildRoot =
    file("${System.getProperty("java.io.tmpdir")}/owntend-gradle-plugin-builds")

subprojects {
    if (project.projectDir.toPath().root == workspaceDriveRoot) {
        val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
        project.layout.buildDirectory.value(newSubprojectBuildDir)
    } else {
        project.layout.buildDirectory.set(
            externalPluginBuildRoot.resolve(project.name),
        )
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

subprojects {
    tasks.withType<JavaCompile>().configureEach {
        sourceCompatibility = JavaVersion.VERSION_17.toString()
        targetCompatibility = JavaVersion.VERSION_17.toString()
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
    delete(externalPluginBuildRoot)
}
