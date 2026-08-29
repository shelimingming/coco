allprojects {
    repositories {
        // 国内镜像优先，减轻 Google/Maven Central 超时与证书问题
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/central") }
        maven { url = uri("https://maven.aliyun.com/repository/public") }
        google()
        // 引擎 jar 约 180MB：国内优先用 flutter-io.cn，避免 googleapis 超时
        maven { url = uri("https://storage.flutter-io.cn/download.flutter.io") }
        maven { url = uri("https://storage.googleapis.com/download.flutter.io") }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
// 部分插件仍写 compileSdk 33，必须在插件脚本执行完后再抬高
subprojects {
    afterEvaluate {
        extensions.findByType(com.android.build.api.dsl.LibraryExtension::class.java)?.compileSdk = 37
        extensions.findByType(com.android.build.api.dsl.ApplicationExtension::class.java)?.compileSdk = 37
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
