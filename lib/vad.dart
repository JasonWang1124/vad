// vad.dart

library vad;

export 'src/vad_handler.dart';
export 'src/vad_handler_base.dart';
export 'src/vad_iterator.dart';
export 'src/vad_event.dart';

// 明確導出非 Web 實作，確保 Windows 支持
export 'src/vad_handler_non_web.dart'
    if (dart.library.html) 'src/vad_handler_web.dart';
export 'src/vad_iterator_non_web.dart'
    if (dart.library.html) 'src/vad_iterator_web.dart';
