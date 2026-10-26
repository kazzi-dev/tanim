# ONNX Runtime is called through JNI; R8 must not strip or rename it.
-keep class ai.onnxruntime.** { *; }
