# 未开启混淆（release 也是 isMinifyEnabled = false）。
# 若以后开启，需要保留 kotlinx.serialization 生成的 serializer：
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.**
-keep,includedescriptorclasses class com.tianzige.tv.**$$serializer { *; }
-keepclassmembers class com.tianzige.tv.** {
    *** Companion;
}
-keepclasseswithmembers class com.tianzige.tv.** {
    kotlinx.serialization.KSerializer serializer(...);
}
