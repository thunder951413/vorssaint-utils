// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct AppHotkeysFeatureStrings {
    let title: String
    let hubDescription: String
    let pageCaption: String
    let panelCaption: String
    let manageButton: String
    let enable: String
    let enableCaption: String
    let frontmostTitle: String
    let frontmostHide: String
    let frontmostHideCaption: String
    let frontmostCycleWindows: String
    let frontmostCycleWindowsCaption: String
    let frontmostKeep: String
    let frontmostKeepCaption: String
    let appsSectionTitle: String
    let activeCountFormat: String
    let addAppButton: String
    let importDockButton: String
    let searchPlaceholder: String
    let emptyTitle: String
    let emptyCaption: String
    let recordShortcut: String
    let removeAppLabel: String
    let moveUpLabel: String
    let moveDownLabel: String
    let runningBadge: String
    let limitReachedFormat: String
    let dockImportEmpty: String
    let dockImportedFormat: String
}

extension FeatureStrings {
    static func appHotkeys(_ language: AppLanguage) -> AppHotkeysFeatureStrings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .tr: return .tr
        case .ru: return .ru
        case .es: return .es
        case .de: return .de
        case .fr: return .fr
        case .it: return .it
        case .ja: return .ja
        case .ko: return .ko
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        }
    }
}

extension AppHotkeysFeatureStrings {
    static let enUS = AppHotkeysFeatureStrings(
        title: "App Hotkeys",
        hubDescription: "Launch or summon favorite apps instantly with dedicated global shortcuts",
        pageCaption: "Bind dedicated global shortcuts to your favorite apps to launch or bring them forward instantly without opening any switcher.",
        panelCaption: "Summon favorite apps with dedicated global shortcuts",
        manageButton: "Manage",
        enable: "Enable App Hotkeys",
        enableCaption: "Listen for assigned application shortcuts anywhere in macOS.",
        frontmostTitle: "When app is already active",
        frontmostHide: "Hide & switch back",
        frontmostHideCaption: "Hides the app and returns focus to your previous app, toggling it on repeat presses.",
        frontmostCycleWindows: "Cycle windows",
        frontmostCycleWindowsCaption: "Rotates through the app’s open windows on the current Space (requires Accessibility).",
        frontmostKeep: "Keep in front",
        frontmostKeepCaption: "Keeps the active app in front and reopens its main window if all windows were closed or minimized.",
        appsSectionTitle: "Application Shortcuts",
        activeCountFormat: "%d active",
        addAppButton: "Add App",
        importDockButton: "Import Dock Apps",
        searchPlaceholder: "Filter apps",
        emptyTitle: "No apps added yet",
        emptyCaption: "Add your favorite apps or import from the Dock, then record a global shortcut for each one.",
        recordShortcut: "Record Shortcut",
        removeAppLabel: "Remove app",
        moveUpLabel: "Move up",
        moveDownLabel: "Move down",
        runningBadge: "Running",
        limitReachedFormat: "You can add up to %d apps. Remove one to add another.",
        dockImportEmpty: "All Dock apps are already in your list.",
        dockImportedFormat: "Added %d apps from the Dock."
    )

    static let ptBR = AppHotkeysFeatureStrings(
        title: "Atalhos de Apps",
        hubDescription: "Abra ou traga seus apps favoritos para a frente instantaneamente com atalhos globais dedicados",
        pageCaption: "Vincule atalhos globais dedicados aos seus apps favoritos para abri-los ou trazê-los para a frente instantaneamente sem abrir nenhum alternador.",
        panelCaption: "Chame apps favoritos com atalhos globais dedicados",
        manageButton: "Gerenciar",
        enable: "Ativar Atalhos de Apps",
        enableCaption: "Ouça os atalhos de aplicativos atribuídos em qualquer lugar do macOS.",
        frontmostTitle: "Quando o app já está ativo",
        frontmostHide: "Ocultar e voltar",
        frontmostHideCaption: "Oculta o app e devolve o foco ao app anterior, alternando ao pressionar novamente.",
        frontmostCycleWindows: "Alternar janelas",
        frontmostCycleWindowsCaption: "Alterna entre as janelas abertas do app no Espaço atual (requer Acessibilidade).",
        frontmostKeep: "Manter na frente",
        frontmostKeepCaption: "Mantém o app ativo na frente e reabre sua janela principal se todas estiverem fechadas ou minimizadas.",
        appsSectionTitle: "Atalhos de Aplicativos",
        activeCountFormat: "%d ativos",
        addAppButton: "Adicionar App",
        importDockButton: "Importar do Dock",
        searchPlaceholder: "Filtrar apps",
        emptyTitle: "Nenhum app adicionado ainda",
        emptyCaption: "Adicione seus apps favoritos ou importe do Dock e grave um atalho global para cada um.",
        recordShortcut: "Gravar Atalho",
        removeAppLabel: "Remover app",
        moveUpLabel: "Mover para cima",
        moveDownLabel: "Mover para baixo",
        runningBadge: "Em execução",
        limitReachedFormat: "Você pode adicionar até %d apps. Remova um para adicionar outro.",
        dockImportEmpty: "Todos os apps do Dock já estão na lista.",
        dockImportedFormat: "%d apps adicionados do Dock."
    )

    static let tr = AppHotkeysFeatureStrings(
        title: "Uygulama Kısayolları",
        hubDescription: "Özel genel kısayollarla favori uygulamaları anında başlatın veya öne getirin",
        pageCaption: "Herhangi bir değiştirici açmadan favori uygulamalarınızı anında başlatmak veya öne getirmek için özel genel kısayollar atayın.",
        panelCaption: "Özel genel kısayollarla favori uygulamaları çağırın",
        manageButton: "Yönet",
        enable: "Uygulama Kısayollarını Etkinleştir",
        enableCaption: "Atanan uygulama kısayollarını macOS genelinde dinleyin.",
        frontmostTitle: "Uygulama zaten etkinken",
        frontmostHide: "Gizle ve geri dön",
        frontmostHideCaption: "Uygulamayı gizler ve odağı önceki uygulamaya geri verir, tekrar basıldığında geçiş yapar.",
        frontmostCycleWindows: "Pencereler arasında gez",
        frontmostCycleWindowsCaption: "Mevcut Alan içindeki açık uygulama pencereleri arasında geçiş yapar (Erişilebilirlik gerekir).",
        frontmostKeep: "Önde tut",
        frontmostKeepCaption: "Etkin uygulamayı önde tutar ve tüm pencereler kapalı veya simge durumundaysa ana pencereyi yeniden açar.",
        appsSectionTitle: "Uygulama Kısayolları",
        activeCountFormat: "%d etkin",
        addAppButton: "Uygulama Ekle",
        importDockButton: "Dock Uygulamalarını İçe Aktar",
        searchPlaceholder: "Uygulamaları filtrele",
        emptyTitle: "Henüz uygulama eklenmedi",
        emptyCaption: "Favori uygulamalarınızı ekleyin veya Dock üzerinden içe aktarın, ardından her biri için genel bir kısayol kaydedin.",
        recordShortcut: "Kısayol Kaydet",
        removeAppLabel: "Uygulamayı kaldır",
        moveUpLabel: "Yukarı taşı",
        moveDownLabel: "Aşağı taşı",
        runningBadge: "Çalışıyor",
        limitReachedFormat: "En fazla %d uygulama ekleyebilirsiniz. Başka eklemek için birini kaldırın.",
        dockImportEmpty: "Tüm Dock uygulamaları zaten listenizde.",
        dockImportedFormat: "Dock üzerinden %d uygulama eklendi."
    )

    static let ru = AppHotkeysFeatureStrings(
        title: "Быстрый вызов программ",
        hubDescription: "Мгновенно запускайте или переключайтесь на любимые приложения глобальными сочетаниями клавиш",
        pageCaption: "Назначьте глобальные сочетания клавиш любимым приложениям, чтобы мгновенно запускать или выводить их на передний план без переключателя.",
        panelCaption: "Вызов избранных приложений глобальными сочетаниями",
        manageButton: "Управлять",
        enable: "Включить быстрый вызов программ",
        enableCaption: "Отслеживать назначенные сочетания клавиш приложений во всей macOS.",
        frontmostTitle: "Если приложение уже активно",
        frontmostHide: "Скрыть и вернуться",
        frontmostHideCaption: "Скрывает приложение и возвращает фокус предыдущему окну при повторном нажатии.",
        frontmostCycleWindows: "Переключать окна",
        frontmostCycleWindowsCaption: "Циклически переключает открытые окна приложения на текущем рабочем пространстве (требуется Универсальный доступ).",
        frontmostKeep: "Оставить спереди",
        frontmostKeepCaption: "Оставляет приложение активным и заново открывает главное окно, если все окна закрыты или свернуты.",
        appsSectionTitle: "Сочетания клавиш приложений",
        activeCountFormat: "%d активно",
        addAppButton: "Добавить приложение",
        importDockButton: "Импорт из Dock",
        searchPlaceholder: "Фильтр приложений",
        emptyTitle: "Приложения еще не добавлены",
        emptyCaption: "Добавьте нужные приложения или импортируйте их из Dock, затем запишите сочетание клавиш для каждого.",
        recordShortcut: "Записать сочетание",
        removeAppLabel: "Удалить приложение",
        moveUpLabel: "Переместить выше",
        moveDownLabel: "Переместить ниже",
        runningBadge: "Запущено",
        limitReachedFormat: "Можно добавить до %d приложений. Удалите одно, чтобы добавить другое.",
        dockImportEmpty: "Все приложения из Dock уже есть в списке.",
        dockImportedFormat: "Добавлено приложений из Dock: %d."
    )

    static let es = AppHotkeysFeatureStrings(
        title: "Atajos de Apps",
        hubDescription: "Abre o trae al frente tus apps favoritas al instante con atajos globales dedicados",
        pageCaption: "Asigna atajos globales dedicados a tus apps favoritas para abrirlas o traerlas al frente al instante sin abrir ningún selector.",
        panelCaption: "Invoca tus apps favoritas con atajos globales dedicados",
        manageButton: "Gestionar",
        enable: "Activar Atajos de Apps",
        enableCaption: "Escucha los atajos de aplicaciones asignados en cualquier lugar de macOS.",
        frontmostTitle: "Cuando la app ya está activa",
        frontmostHide: "Ocultar y volver",
        frontmostHideCaption: "Oculta la app y devuelve el foco a la app anterior, alternándola al volver a pulsar.",
        frontmostCycleWindows: "Alternar ventanas",
        frontmostCycleWindowsCaption: "Recorre las ventanas abiertas de la app en el espacio actual (requiere Accesibilidad).",
        frontmostKeep: "Mantener al frente",
        frontmostKeepCaption: "Mantiene la app activa al frente y reabre su ventana principal si todas estaban cerradas o minimizadas.",
        appsSectionTitle: "Atajos de Aplicaciones",
        activeCountFormat: "%d activos",
        addAppButton: "Añadir app",
        importDockButton: "Importar del Dock",
        searchPlaceholder: "Filtrar apps",
        emptyTitle: "Aún no hay apps añadidas",
        emptyCaption: "Añade tus apps favoritas o impórtalas del Dock y graba un atajo global para cada una.",
        recordShortcut: "Grabar atajo",
        removeAppLabel: "Quitar app",
        moveUpLabel: "Subir",
        moveDownLabel: "Bajar",
        runningBadge: "En ejecución",
        limitReachedFormat: "Puedes añadir hasta %d apps. Quita una para añadir otra.",
        dockImportEmpty: "Todas las apps del Dock ya están en tu lista.",
        dockImportedFormat: "Se añadieron %d apps del Dock."
    )

    static let de = AppHotkeysFeatureStrings(
        title: "App-Kurzbefehle",
        hubDescription: "Lieblings-Apps sofort per eigenem globalen Kurzbefehl starten oder nach vorn holen",
        pageCaption: "Weise deinen wichtigsten Apps eigene globale Kurzbefehle zu, um sie ohne Umschalter sofort zu starten oder in den Vordergrund zu holen.",
        panelCaption: "Lieblings-Apps per globalem Kurzbefehl aufrufen",
        manageButton: "Verwalten",
        enable: "App-Kurzbefehle aktivieren",
        enableCaption: "Zugewiesene App-Kurzbefehle überall in macOS erkennen.",
        frontmostTitle: "Wenn die App bereits aktiv ist",
        frontmostHide: "Ausblenden & zurück",
        frontmostHideCaption: "Blendet die App aus und gibt den Fokus an die vorherige App zurück.",
        frontmostCycleWindows: "Fenster durchschalten",
        frontmostCycleWindowsCaption: "Wechselt zwischen offenen Fenstern der App auf dem aktuellen Space (erfordert Bedienungshilfen).",
        frontmostKeep: "Vorn behalten",
        frontmostKeepCaption: "Hält die aktive App im Vordergrund und öffnet ihr Hauptfenster erneut, falls alle geschlossen oder minimiert waren.",
        appsSectionTitle: "App-Kurzbefehle",
        activeCountFormat: "%d aktiv",
        addAppButton: "App hinzufügen",
        importDockButton: "Dock-Apps importieren",
        searchPlaceholder: "Apps filtern",
        emptyTitle: "Noch keine Apps hinzugefügt",
        emptyCaption: "Füge deine bevorzugten Apps hinzu oder importiere sie aus dem Dock und nimm für jede einen Kurzbefehl auf.",
        recordShortcut: "Kurzbefehl aufnehmen",
        removeAppLabel: "App entfernen",
        moveUpLabel: "Nach oben",
        moveDownLabel: "Nach unten",
        runningBadge: "Aktiv",
        limitReachedFormat: "Du kannst bis zu %d Apps hinzufügen. Entferne eine, um eine weitere hinzuzufügen.",
        dockImportEmpty: "Alle Dock-Apps sind bereits in deiner Liste.",
        dockImportedFormat: "%d Apps aus dem Dock hinzugefügt."
    )

    static let fr = AppHotkeysFeatureStrings(
        title: "Raccourcis d’apps",
        hubDescription: "Lancez ou affichez instantanément vos apps favorites avec des raccourcis globaux dédiés",
        pageCaption: "Associez des raccourcis globaux dédiés à vos apps favorites pour les lancer ou les amener au premier plan instantanément sans sélecteur.",
        panelCaption: "Appelez vos apps favorites avec des raccourcis globaux dédiés",
        manageButton: "Gérer",
        enable: "Activer les raccourcis d’apps",
        enableCaption: "Écouter les raccourcis d’applications attribués partout dans macOS.",
        frontmostTitle: "Lorsque l’app est déjà au premier plan",
        frontmostHide: "Masquer et revenir",
        frontmostHideCaption: "Masque l’app et rend le focus à l’application précédente lors d’un nouvel appui.",
        frontmostCycleWindows: "Parcourir les fenêtres",
        frontmostCycleWindowsCaption: "Fait défiler les fenêtres ouvertes de l’app sur l’espace actuel (nécessite Accessibilité).",
        frontmostKeep: "Garder devant",
        frontmostKeepCaption: "Garde l’app active au premier plan et rouvre sa fenêtre principale si toutes étaient fermées ou réduites.",
        appsSectionTitle: "Raccourcis d’applications",
        activeCountFormat: "%d actifs",
        addAppButton: "Ajouter une app",
        importDockButton: "Importer du Dock",
        searchPlaceholder: "Filtrer les apps",
        emptyTitle: "Aucune app ajoutée",
        emptyCaption: "Ajoutez vos apps favorites ou importez-les du Dock, puis enregistrez un raccourci global pour chacune.",
        recordShortcut: "Enregistrer",
        removeAppLabel: "Retirer l’app",
        moveUpLabel: "Monter",
        moveDownLabel: "Descendre",
        runningBadge: "En cours",
        limitReachedFormat: "Vous pouvez ajouter jusqu’à %d apps. Retirez-en une pour en ajouter une autre.",
        dockImportEmpty: "Toutes les apps du Dock figurent déjà dans la liste.",
        dockImportedFormat: "%d apps ajoutées depuis le Dock."
    )

    static let it = AppHotkeysFeatureStrings(
        title: "Scorciatoie App",
        hubDescription: "Avvia o porta in primo piano all’istante le tue app preferite con scorciatoie globali dedicate",
        pageCaption: "Assegna scorciatoie globali dedicate alle tue app preferite per avviarle o portarle subito in primo piano senza aprire alcun selettore.",
        panelCaption: "Richiama le app preferite con scorciatoie globali dedicate",
        manageButton: "Gestisci",
        enable: "Abilita Scorciatoie App",
        enableCaption: "Ascolta le scorciatoie delle applicazioni assegnate ovunque in macOS.",
        frontmostTitle: "Quando l’app è già attiva",
        frontmostHide: "Nascondi e torna indietro",
        frontmostHideCaption: "Nasconde l’app e restituisce il fuoco all’applicazione precedente premendo di nuovo.",
        frontmostCycleWindows: "Scorri finestre",
        frontmostCycleWindowsCaption: "Passa tra le finestre aperte dell’app nello spazio attuale (richiede Accessibilità).",
        frontmostKeep: "Mantieni davanti",
        frontmostKeepCaption: "Mantiene l’app attiva in primo piano e riapre la finestra principale se tutte erano chiuse o contratte.",
        appsSectionTitle: "Scorciatoie Applicazioni",
        activeCountFormat: "%d attive",
        addAppButton: "Aggiungi app",
        importDockButton: "Importa dal Dock",
        searchPlaceholder: "Filtra app",
        emptyTitle: "Nessuna app aggiunta",
        emptyCaption: "Aggiungi le tue app preferite o importale dal Dock, poi registra una scorciatoia globale per ciascuna.",
        recordShortcut: "Registra scorciatoia",
        removeAppLabel: "Rimuovi app",
        moveUpLabel: "Sposta su",
        moveDownLabel: "Sposta giù",
        runningBadge: "In esecuzione",
        limitReachedFormat: "Puoi aggiungere fino a %d app. Rimuovine una per aggiungerne un’altra.",
        dockImportEmpty: "Tutte le app del Dock sono già nell’elenco.",
        dockImportedFormat: "Aggiunte %d app dal Dock."
    )

    static let ja = AppHotkeysFeatureStrings(
        title: "アプリ起動ホットキー",
        hubDescription: "専用のグローバルショートカットでよく使うアプリを瞬時に起動・前面表示",
        pageCaption: "よく使うアプリに専用のグローバルショートカットを割り当て、スイッチャーを開かずに瞬時に起動・切り替えできます。",
        panelCaption: "専用ショートカットでお気に入りアプリを即座に呼び出す",
        manageButton: "管理",
        enable: "アプリ起動ホットキーを有効にする",
        enableCaption: "macOS全体で設定済みのアプリショートカットを受け付けます。",
        frontmostTitle: "対象アプリがすでに最前面にあるとき",
        frontmostHide: "隠して前のアプリに戻る",
        frontmostHideCaption: "現在のアプリを非表示にして直前のアプリへフォーカスを戻します。もう一度押すと再表示します。",
        frontmostCycleWindows: "ウインドウを切り替え",
        frontmostCycleWindowsCaption: "現在の操作スペースにある同じアプリの開いているウインドウを順番に切り替えます（アクセシビリティ権限が必要）。",
        frontmostKeep: "最前面のままにする",
        frontmostKeepCaption: "アプリを最前面に保ち、ウインドウがすべて閉じているか最小化されている場合はメインウインドウを再度開きます。",
        appsSectionTitle: "アプリのショートカット一覧",
        activeCountFormat: "%d 件有効",
        addAppButton: "アプリを追加",
        importDockButton: "Dockのアプリを読み込む",
        searchPlaceholder: "アプリを絞り込む",
        emptyTitle: "アプリがまだ登録されていません",
        emptyCaption: "よく使うアプリを追加するかDockから読み込み、それぞれにグローバルショートカットを設定してください。",
        recordShortcut: "ショートカットを記録",
        removeAppLabel: "アプリを削除",
        moveUpLabel: "上へ移動",
        moveDownLabel: "下へ移動",
        runningBadge: "起動中",
        limitReachedFormat: "登録できるアプリは最大 %d 件です。新しく追加するには1つ削除してください。",
        dockImportEmpty: "Dockのアプリはすべてリストに追加済みです。",
        dockImportedFormat: "Dockから %d 件のアプリを追加しました。"
    )

    static let ko = AppHotkeysFeatureStrings(
        title: "앱 빠른 호출",
        hubDescription: "전용 전역 단축키로 자주 쓰는 앱을 즉시 실행하거나 앞으로 가져오기",
        pageCaption: "자주 사용하는 앱에 전용 전역 단축키를 지정하여 전환기 없이 즉시 실행하거나 맨 앞으로 가져옵니다.",
        panelCaption: "전용 전역 단축키로 즐겨찾는 앱 즉시 호출",
        manageButton: "관리",
        enable: "앱 빠른 호출 활성화",
        enableCaption: "macOS 어디서나 지정된 앱 단축키에 반응합니다.",
        frontmostTitle: "앱이 이미 맨 앞에 있을 때",
        frontmostHide: "숨기고 이전 앱으로 전환",
        frontmostHideCaption: "현재 앱을 숨기고 직전 앱으로 포커스를 돌려보내며, 반복 입력 시 빠르게 표시/숨김을 전환합니다.",
        frontmostCycleWindows: "같은 앱 창 순환",
        frontmostCycleWindowsCaption: "현재 데스크탑 공간에 열린 해당 앱의 창들을 순서대로 전환합니다(손쉬운 사용 권한 필요).",
        frontmostKeep: "맨 앞에 유지",
        frontmostKeepCaption: "활성 앱을 맨 앞에 유지하며, 모든 창이 닫혀 있거나 최소화된 경우 기본 창을 다시 엽니다.",
        appsSectionTitle: "앱 단축키 목록",
        activeCountFormat: "%d개 활성",
        addAppButton: "앱 추가",
        importDockButton: "Dock 앱 가져오기",
        searchPlaceholder: "앱 필터링",
        emptyTitle: "추가된 앱이 없습니다",
        emptyCaption: "자주 쓰는 앱을 추가하거나 Dock에서 가져온 뒤 각 앱의 전역 단축키를 지정하세요.",
        recordShortcut: "단축키 지정",
        removeAppLabel: "앱 제거",
        moveUpLabel: "위로 이동",
        moveDownLabel: "아래로 이동",
        runningBadge: "실행 중",
        limitReachedFormat: "최대 %d개의 앱까지 추가할 수 있습니다. 하나를 제거한 뒤 추가하세요.",
        dockImportEmpty: "Dock의 모든 앱이 이미 목록에 있습니다.",
        dockImportedFormat: "Dock에서 앱 %d개를 추가했습니다."
    )

    static let zhHans = AppHotkeysFeatureStrings(
        title: "应用速启",
        hubDescription: "为常用应用绑定专属全局快捷键，随时一键启动或唤醒到前台",
        pageCaption: "为常用应用设定专属全局快捷键，无需呼出任何切换面板即可随时一键启动或唤醒到前台。",
        panelCaption: "通过专属全局快捷键一键唤醒常用应用",
        manageButton: "管理",
        enable: "启用应用速启",
        enableCaption: "在系统任意位置响应已配置的应用全局快捷键。",
        frontmostTitle: "当目标应用已在最前台时",
        frontmostHide: "隐藏并切回上一应用",
        frontmostHideCaption: "隐藏当前应用并将焦点交还给上一个活动应用，再次按下即可重新唤醒。",
        frontmostCycleWindows: "循环同应用窗口",
        frontmostCycleWindowsCaption: "在该应用当前桌面空间的多个打开窗口之间依次轮换（需要辅助功能权限）。",
        frontmostKeep: "保持在前台",
        frontmostKeepCaption: "保持当前应用处于前台；若窗口已全部关闭或最小化则重新打开主窗口。",
        appsSectionTitle: "应用快捷键列表",
        activeCountFormat: "%d 个生效中",
        addAppButton: "添加应用",
        importDockButton: "导入程序坞应用",
        searchPlaceholder: "筛选应用",
        emptyTitle: "尚未添加任何应用",
        emptyCaption: "点击上方按钮添加常用应用或一键导入程序坞应用，然后为它们录制专属唤醒快捷键。",
        recordShortcut: "录制快捷键",
        removeAppLabel: "移除应用",
        moveUpLabel: "上移",
        moveDownLabel: "下移",
        runningBadge: "运行中",
        limitReachedFormat: "最多可添加 %d 个应用，请先移除一个后再添加。",
        dockImportEmpty: "程序坞中的应用均已在列表中。",
        dockImportedFormat: "已从程序坞导入 %d 个应用。"
    )

    static let zhTW = AppHotkeysFeatureStrings(
        title: "App 速啟",
        hubDescription: "為常用 App 綁定專屬全域快速鍵，隨時一鍵啟動或喚醒至最前景",
        pageCaption: "為常用 App 設定專屬全域快速鍵，無需開啟切換面板即可隨時一鍵啟動或帶到最前景。",
        panelCaption: "透過專屬全域快速鍵一鍵喚醒常用 App",
        manageButton: "管理",
        enable: "啟用 App 速啟",
        enableCaption: "在系統任意位置回應已設定的 App 全域快速鍵。",
        frontmostTitle: "當目標 App 已在最前景時",
        frontmostHide: "隱藏並切回上一個 App",
        frontmostHideCaption: "隱藏目前 App 並將焦點交還給上一個使用中 App，再次按下即可重新喚醒。",
        frontmostCycleWindows: "循環同 App 視窗",
        frontmostCycleWindowsCaption: "在該 App 目前桌面空間的多個開啟視窗之間依序切換（需要輔助使用權限）。",
        frontmostKeep: "保持在最前景",
        frontmostKeepCaption: "保持目前 App 位於最前景；若視窗均已關閉或最小化則重新打開主視窗。",
        appsSectionTitle: "App 快速鍵列表",
        activeCountFormat: "%d 個生效中",
        addAppButton: "加入 App",
        importDockButton: "匯入 Dock 應用",
        searchPlaceholder: "篩選 App",
        emptyTitle: "尚未加入任何 App",
        emptyCaption: "點擊上方按鈕加入常用 App 或從 Dock 匯入，接著為每個 App 錄製專屬快速鍵。",
        recordShortcut: "錄製快速鍵",
        removeAppLabel: "移除 App",
        moveUpLabel: "上移",
        moveDownLabel: "下移",
        runningBadge: "執行中",
        limitReachedFormat: "最多可加入 %d 個 App，請先移除一個後再新增。",
        dockImportEmpty: "Dock 中的 App 均已在列表中。",
        dockImportedFormat: "已從 Dock 匯入 %d 個 App。"
    )

    static let zhHK = AppHotkeysFeatureStrings(
        title: "App 速啟",
        hubDescription: "為常用 App 綁定專屬全域快捷鍵，隨時一鍵啟動或喚醒至最前景",
        pageCaption: "為常用 App 設定專屬全域快捷鍵，無需開啟切換面板即可隨時一鍵啟動或帶到最前景。",
        panelCaption: "透過專屬全域快捷鍵一鍵喚醒常用 App",
        manageButton: "管理",
        enable: "啟用 App 速啟",
        enableCaption: "在系統任意位置回應已設定的 App 全域快捷鍵。",
        frontmostTitle: "當目標 App 已在最前景時",
        frontmostHide: "隱藏並切回上一個 App",
        frontmostHideCaption: "隱藏目前 App 並將焦點交還給上一個使用中 App，再次按下即可重新喚醒。",
        frontmostCycleWindows: "循環同 App 視窗",
        frontmostCycleWindowsCaption: "在該 App 目前桌面空間的多個開啟視窗之間依序切換（需要輔助使用權限）。",
        frontmostKeep: "保持在最前景",
        frontmostKeepCaption: "保持目前 App 位於最前景；若視窗均已關閉或縮到最小則重新開啟主視窗。",
        appsSectionTitle: "App 快捷鍵列表",
        activeCountFormat: "%d 個生效中",
        addAppButton: "加入 App",
        importDockButton: "匯入 Dock 應用",
        searchPlaceholder: "篩選 App",
        emptyTitle: "尚未加入任何 App",
        emptyCaption: "點擊上方按鈕加入常用 App 或從 Dock 匯入，然後為每個 App 錄製專屬快捷鍵。",
        recordShortcut: "錄製快捷鍵",
        removeAppLabel: "移除 App",
        moveUpLabel: "上移",
        moveDownLabel: "下移",
        runningBadge: "執行中",
        limitReachedFormat: "最多可加入 %d 個 App，請先移除一個後再新增。",
        dockImportEmpty: "Dock 中的 App 均已在列表中。",
        dockImportedFormat: "已從 Dock 匯入 %d 個 App。"
    )
}
