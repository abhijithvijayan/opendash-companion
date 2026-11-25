# Keep the gRPC / protobuf-lite provisioning stubs alive under R8.
# They are reflection-based, so minification would otherwise strip or rename them.
-keep class io.grpc.** { *; }
-keep class com.google.protobuf.** { *; }
-keep class wifican.** { *; }
-dontwarn io.grpc.**
-dontwarn com.google.protobuf.**
