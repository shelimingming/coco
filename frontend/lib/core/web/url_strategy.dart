import 'url_strategy_stub.dart'
    if (dart.library.html) 'url_strategy_web.dart'
    as impl;

/// 启动前配置 Web URL 策略（/invite/xxx 而非 #/invite/xxx）。
void configureUrlStrategy() => impl.configureUrlStrategy();
