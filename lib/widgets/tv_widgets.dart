/// Widgets otimizados para TV/Fire TV/Android TV
/// 
/// Este pacote contém componentes especialmente desenvolvidos para
/// proporcionar uma experiência de usuário excelente em TV.
/// 
/// Inclui:
/// - [TVFocusWrapper] - Wrapper para elementos focáveis
/// - [TVNumericKeyboard] - Teclado numérico navegável por D-Pad
/// - [TVPinDialog] - Dialog de PIN para controle parental
/// - [TVLoadingIndicator] - Indicador de carregamento animado
/// - [TVErrorWidget] - Widget de erro com retry
/// - [TVEmptyWidget] - Widget para estados vazios
/// - [TVToast] - Sistema de notificações toast
/// - [TVQuickAccessSidebar] - Sidebar de acesso rápido
/// - [TVScreensaver] - Screensaver para prevenir burn-in
/// - [ContinueWatchingCard] - Card de "Continue Assistindo"
/// - [QuickCategoriesBar] - Barra de categorias navegável
library tv_widgets;

export 'tv_focus_wrapper.dart' hide AnimatedBuilder;
export 'tv_numeric_keyboard.dart';
export 'tv_loading_widget.dart';
export 'tv_toast.dart';
export 'tv_quick_access_sidebar.dart' hide AnimatedBuilder;
export 'tv_screensaver.dart' hide AnimatedBuilder;
export 'continue_watching_card.dart';
