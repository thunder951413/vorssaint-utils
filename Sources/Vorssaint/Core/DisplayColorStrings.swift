// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct DisplayColorFeatureStrings {
    let title: String
    let hubDescription: String
    let enable: String
    let enableCaption: String
    let modeSun: String
    let modeManual: String
    let phaseDay: String
    let phaseSunset: String
    let phaseNight: String
    let whiteBalance: String
    let tint: String
    let tintStrength: String
    let clearTint: String
    /// Sunrise time, then sunset time.
    let sunTimesFormat: String
    let fallbackTimes: String
    let bedtime: String
    let transition: String
    let minutesFormat: String
    let locate: String
    let locating: String
    let locationFailed: String
    let latitude: String
    let longitude: String
    let clearLocation: String
    /// The current phase's name.
    let nowFormat: String
    let fluxWarning: String
    let scheduleOptions: String

    func phase(_ phase: DisplayColorPhase) -> String {
        switch phase {
        case .day: return phaseDay
        case .sunset: return phaseSunset
        case .night: return phaseNight
        }
    }

    func mode(_ mode: DisplayColorMode) -> String {
        switch mode {
        case .sun: return modeSun
        case .manual: return modeManual
        }
    }
}

extension FeatureStrings {
    static func displayColor(_ language: AppLanguage) -> DisplayColorFeatureStrings {
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

extension DisplayColorFeatureStrings {
    static let enUS = DisplayColorFeatureStrings(
        title: "Screen Color",
        hubDescription: "Warm or tint every screen, following sunrise and sunset or one fixed look",
        enable: "Color filter",
        enableCaption: "Changes the color of every screen. Works together with software dimming.",
        modeSun: "Sunrise & sunset",
        modeManual: "Manual",
        phaseDay: "Day",
        phaseSunset: "Sunset",
        phaseNight: "Night",
        whiteBalance: "White balance",
        tint: "Tint",
        tintStrength: "Strength",
        clearTint: "Clear tint",
        sunTimesFormat: "Sunrise %@ · Sunset %@",
        fallbackTimes: "No location set: sunrise and sunset count as 07:00 and 19:00.",
        bedtime: "Bedtime",
        transition: "Fade",
        minutesFormat: "%d min",
        locate: "Use current location",
        locating: "Locating…",
        locationFailed: "Location unavailable. Check Location Services in System Settings, or enter coordinates.",
        latitude: "Latitude",
        longitude: "Longitude",
        clearLocation: "Clear location",
        nowFormat: "Now: %@",
        fluxWarning: "f.lux is running and changes the same screen colors, so the two keep overriding each other. Quit f.lux to use this filter.",
        scheduleOptions: "Schedule")

    static let ptBR = DisplayColorFeatureStrings(
        title: "Cor da tela",
        hubDescription: "Aquece ou tinge todas as telas, seguindo o nascer e o pôr do sol ou um visual fixo",
        enable: "Filtro de cor",
        enableCaption: "Muda a cor de todas as telas. Funciona junto com o escurecimento por software.",
        modeSun: "Nascer e pôr do sol",
        modeManual: "Manual",
        phaseDay: "Dia",
        phaseSunset: "Pôr do sol",
        phaseNight: "Noite",
        whiteBalance: "Balanço de branco",
        tint: "Matiz",
        tintStrength: "Intensidade",
        clearTint: "Remover matiz",
        sunTimesFormat: "Nascer %@ · Pôr %@",
        fallbackTimes: "Sem localização: o nascer e o pôr do sol contam como 07:00 e 19:00.",
        bedtime: "Hora de dormir",
        transition: "Transição",
        minutesFormat: "%d min",
        locate: "Usar localização atual",
        locating: "Localizando…",
        locationFailed: "Localização indisponível. Verifique os Serviços de Localização nos Ajustes do Sistema ou digite as coordenadas.",
        latitude: "Latitude",
        longitude: "Longitude",
        clearLocation: "Limpar localização",
        nowFormat: "Agora: %@",
        fluxWarning: "O f.lux está aberto e muda as mesmas cores da tela, então um desfaz o outro. Feche o f.lux para usar este filtro.",
        scheduleOptions: "Agenda")

    static let tr = DisplayColorFeatureStrings(
        title: "Ekran Rengi",
        hubDescription: "Tüm ekranları gün doğumu ve batımına göre ya da sabit bir görünümle ısıtır veya renklendirir",
        enable: "Renk filtresi",
        enableCaption: "Tüm ekranların rengini değiştirir. Yazılımsal karartmayla birlikte çalışır.",
        modeSun: "Gün doğumu ve batımı",
        modeManual: "Elle",
        phaseDay: "Gündüz",
        phaseSunset: "Gün batımı",
        phaseNight: "Gece",
        whiteBalance: "Beyaz dengesi",
        tint: "Renk tonu",
        tintStrength: "Yoğunluk",
        clearTint: "Tonu temizle",
        sunTimesFormat: "Doğuş %@ · Batış %@",
        fallbackTimes: "Konum yok: gün doğumu ve batımı 07:00 ve 19:00 sayılır.",
        bedtime: "Yatma saati",
        transition: "Geçiş",
        minutesFormat: "%d dk",
        locate: "Geçerli konumu kullan",
        locating: "Konum bulunuyor…",
        locationFailed: "Konum alınamadı. Sistem Ayarları’nda Konum Servisleri’ni denetleyin veya koordinat girin.",
        latitude: "Enlem",
        longitude: "Boylam",
        clearLocation: "Konumu temizle",
        nowFormat: "Şimdi: %@",
        fluxWarning: "f.lux çalışıyor ve aynı ekran renklerini değiştiriyor, bu yüzden ikisi birbirini bozuyor. Bu filtreyi kullanmak için f.lux’tan çıkın.",
        scheduleOptions: "Zamanlama")

    static let ru = DisplayColorFeatureStrings(
        title: "Цвет экрана",
        hubDescription: "Делает все экраны теплее или подкрашивает их по восходу и закату или в одном режиме",
        enable: "Цветовой фильтр",
        enableCaption: "Меняет цвет всех экранов. Работает вместе с программным затемнением.",
        modeSun: "Восход и закат",
        modeManual: "Вручную",
        phaseDay: "День",
        phaseSunset: "Закат",
        phaseNight: "Ночь",
        whiteBalance: "Баланс белого",
        tint: "Оттенок",
        tintStrength: "Сила",
        clearTint: "Убрать оттенок",
        sunTimesFormat: "Восход %@ · Закат %@",
        fallbackTimes: "Место не задано: восход и закат считаются в 07:00 и 19:00.",
        bedtime: "Время сна",
        transition: "Переход",
        minutesFormat: "%d мин",
        locate: "Текущее местоположение",
        locating: "Определение…",
        locationFailed: "Местоположение недоступно. Проверьте Службы геолокации в Системных настройках или введите координаты.",
        latitude: "Широта",
        longitude: "Долгота",
        clearLocation: "Сбросить место",
        nowFormat: "Сейчас: %@",
        fluxWarning: "Запущен f.lux, он меняет те же цвета экрана, и программы перебивают друг друга. Закройте f.lux, чтобы пользоваться этим фильтром.",
        scheduleOptions: "Расписание")

    static let es = DisplayColorFeatureStrings(
        title: "Color de pantalla",
        hubDescription: "Calienta o tiñe todas las pantallas según el amanecer y el atardecer o con un aspecto fijo",
        enable: "Filtro de color",
        enableCaption: "Cambia el color de todas las pantallas. Funciona junto con la atenuación por software.",
        modeSun: "Amanecer y atardecer",
        modeManual: "Manual",
        phaseDay: "Día",
        phaseSunset: "Atardecer",
        phaseNight: "Noche",
        whiteBalance: "Balance de blancos",
        tint: "Tono",
        tintStrength: "Intensidad",
        clearTint: "Quitar tono",
        sunTimesFormat: "Amanecer %@ · Atardecer %@",
        fallbackTimes: "Sin ubicación: el amanecer y el atardecer cuentan como 07:00 y 19:00.",
        bedtime: "Hora de dormir",
        transition: "Transición",
        minutesFormat: "%d min",
        locate: "Usar ubicación actual",
        locating: "Buscando ubicación…",
        locationFailed: "Ubicación no disponible. Revisa Localización en Ajustes del Sistema o introduce las coordenadas.",
        latitude: "Latitud",
        longitude: "Longitud",
        clearLocation: "Borrar ubicación",
        nowFormat: "Ahora: %@",
        fluxWarning: "f.lux está abierto y cambia los mismos colores de pantalla, así que uno deshace al otro. Cierra f.lux para usar este filtro.",
        scheduleOptions: "Horario")

    static let de = DisplayColorFeatureStrings(
        title: "Bildschirmfarbe",
        hubDescription: "Macht alle Bildschirme wärmer oder tönt sie, nach Sonnenauf- und -untergang oder fest eingestellt",
        enable: "Farbfilter",
        enableCaption: "Ändert die Farbe aller Bildschirme. Funktioniert zusammen mit dem Software-Dimmen.",
        modeSun: "Sonnenauf- und -untergang",
        modeManual: "Manuell",
        phaseDay: "Tag",
        phaseSunset: "Sonnenuntergang",
        phaseNight: "Nacht",
        whiteBalance: "Weißabgleich",
        tint: "Tönung",
        tintStrength: "Stärke",
        clearTint: "Tönung entfernen",
        sunTimesFormat: "Aufgang %@ · Untergang %@",
        fallbackTimes: "Kein Ort festgelegt: Sonnenauf- und -untergang gelten als 07:00 und 19:00.",
        bedtime: "Schlafenszeit",
        transition: "Übergang",
        minutesFormat: "%d Min.",
        locate: "Aktuellen Ort verwenden",
        locating: "Ort wird ermittelt …",
        locationFailed: "Ort nicht verfügbar. Prüfe die Ortungsdienste in den Systemeinstellungen oder gib Koordinaten ein.",
        latitude: "Breitengrad",
        longitude: "Längengrad",
        clearLocation: "Ort entfernen",
        nowFormat: "Jetzt: %@",
        fluxWarning: "f.lux läuft und ändert dieselben Bildschirmfarben, sodass sich beide gegenseitig überschreiben. Beende f.lux, um diesen Filter zu nutzen.",
        scheduleOptions: "Zeitplan")

    static let fr = DisplayColorFeatureStrings(
        title: "Couleur de l’écran",
        hubDescription: "Réchauffe ou teinte tous les écrans selon le lever et le coucher du soleil, ou avec un réglage fixe",
        enable: "Filtre de couleur",
        enableCaption: "Change la couleur de tous les écrans. Fonctionne avec l’atténuation logicielle.",
        modeSun: "Lever et coucher du soleil",
        modeManual: "Manuel",
        phaseDay: "Jour",
        phaseSunset: "Coucher du soleil",
        phaseNight: "Nuit",
        whiteBalance: "Balance des blancs",
        tint: "Teinte",
        tintStrength: "Intensité",
        clearTint: "Retirer la teinte",
        sunTimesFormat: "Lever %@ · Coucher %@",
        fallbackTimes: "Aucun lieu défini\u{00A0}: le lever et le coucher du soleil comptent pour 07:00 et 19:00.",
        bedtime: "Heure du coucher",
        transition: "Transition",
        minutesFormat: "%d min",
        locate: "Utiliser la position actuelle",
        locating: "Localisation…",
        locationFailed: "Position indisponible. Vérifiez le Service de localisation dans Réglages Système ou saisissez des coordonnées.",
        latitude: "Latitude",
        longitude: "Longitude",
        clearLocation: "Effacer la position",
        nowFormat: "Maintenant\u{00A0}: %@",
        fluxWarning: "f.lux est ouvert et modifie les mêmes couleurs d’écran, si bien que l’un annule l’autre. Quittez f.lux pour utiliser ce filtre.",
        scheduleOptions: "Programmation")

    static let it = DisplayColorFeatureStrings(
        title: "Colore dello schermo",
        hubDescription: "Scalda o tinge tutti gli schermi seguendo alba e tramonto o con un aspetto fisso",
        enable: "Filtro colore",
        enableCaption: "Cambia il colore di tutti gli schermi. Funziona insieme all’attenuazione software.",
        modeSun: "Alba e tramonto",
        modeManual: "Manuale",
        phaseDay: "Giorno",
        phaseSunset: "Tramonto",
        phaseNight: "Notte",
        whiteBalance: "Bilanciamento del bianco",
        tint: "Tinta",
        tintStrength: "Intensità",
        clearTint: "Rimuovi tinta",
        sunTimesFormat: "Alba %@ · Tramonto %@",
        fallbackTimes: "Nessuna posizione: alba e tramonto valgono 07:00 e 19:00.",
        bedtime: "Ora di dormire",
        transition: "Transizione",
        minutesFormat: "%d min",
        locate: "Usa la posizione attuale",
        locating: "Localizzazione…",
        locationFailed: "Posizione non disponibile. Controlla Localizzazione in Impostazioni di Sistema o inserisci le coordinate.",
        latitude: "Latitudine",
        longitude: "Longitudine",
        clearLocation: "Cancella posizione",
        nowFormat: "Ora: %@",
        fluxWarning: "f.lux è aperto e modifica gli stessi colori dello schermo, quindi l’uno annulla l’altro. Chiudi f.lux per usare questo filtro.",
        scheduleOptions: "Programma")

    static let ja = DisplayColorFeatureStrings(
        title: "画面の色",
        hubDescription: "日の出と日の入りに合わせて、または固定の設定で、すべての画面を暖色にしたり色味を付けたりします",
        enable: "カラーフィルタ",
        enableCaption: "すべての画面の色を変えます。ソフトウェア調光と一緒に使えます。",
        modeSun: "日の出・日の入り",
        modeManual: "手動",
        phaseDay: "日中",
        phaseSunset: "夕方",
        phaseNight: "夜間",
        whiteBalance: "ホワイトバランス",
        tint: "色味",
        tintStrength: "強さ",
        clearTint: "色味を解除",
        sunTimesFormat: "日の出 %@ · 日の入り %@",
        fallbackTimes: "位置が未設定のため、日の出を 07:00、日の入りを 19:00 として計算します。",
        bedtime: "就寝時刻",
        transition: "切り替え時間",
        minutesFormat: "%d 分",
        locate: "現在地を使用",
        locating: "位置を取得中…",
        locationFailed: "位置を取得できません。システム設定の位置情報サービスを確認するか、座標を入力してください。",
        latitude: "緯度",
        longitude: "経度",
        clearLocation: "位置を消去",
        nowFormat: "現在：%@",
        fluxWarning: "f.lux が起動していて同じ画面の色を変更するため、互いに上書きし合います。このフィルタを使うには f.lux を終了してください。",
        scheduleOptions: "スケジュール")

    static let ko = DisplayColorFeatureStrings(
        title: "화면 색상",
        hubDescription: "일출과 일몰에 맞추거나 고정된 설정으로 모든 화면을 따뜻하게 하거나 색조를 더합니다",
        enable: "색상 필터",
        enableCaption: "모든 화면의 색상을 바꿉니다. 소프트웨어 밝기 조절과 함께 동작합니다.",
        modeSun: "일출과 일몰",
        modeManual: "수동",
        phaseDay: "낮",
        phaseSunset: "해 질 녘",
        phaseNight: "밤",
        whiteBalance: "화이트 밸런스",
        tint: "색조",
        tintStrength: "강도",
        clearTint: "색조 지우기",
        sunTimesFormat: "일출 %@ · 일몰 %@",
        fallbackTimes: "위치가 없어 일출과 일몰을 07:00과 19:00으로 계산합니다.",
        bedtime: "취침 시간",
        transition: "전환 시간",
        minutesFormat: "%d분",
        locate: "현재 위치 사용",
        locating: "위치 확인 중…",
        locationFailed: "위치를 가져올 수 없습니다. 시스템 설정의 위치 서비스를 확인하거나 좌표를 입력하세요.",
        latitude: "위도",
        longitude: "경도",
        clearLocation: "위치 지우기",
        nowFormat: "현재: %@",
        fluxWarning: "f.lux가 실행 중이며 같은 화면 색상을 바꾸고 있어 서로 덮어씁니다. 이 필터를 사용하려면 f.lux를 종료하세요.",
        scheduleOptions: "일정")

    static let zhHans = DisplayColorFeatureStrings(
        title: "屏幕色彩",
        hubDescription: "按日出日落或固定设置，让所有屏幕变暖或偏向某种颜色",
        enable: "色彩滤镜",
        enableCaption: "改变所有屏幕的颜色，可与软件调暗同时使用。",
        modeSun: "日出日落",
        modeManual: "手动",
        phaseDay: "白天",
        phaseSunset: "日落",
        phaseNight: "夜间",
        whiteBalance: "白平衡",
        tint: "偏色",
        tintStrength: "幅度",
        clearTint: "清除偏色",
        sunTimesFormat: "日出 %@ · 日落 %@",
        fallbackTimes: "未设置位置：按 07:00 日出、19:00 日落计算。",
        bedtime: "就寝时间",
        transition: "渐变时长",
        minutesFormat: "%d 分钟",
        locate: "使用当前位置",
        locating: "正在定位…",
        locationFailed: "无法获取位置。请在系统设置中检查定位服务，或手动输入经纬度。",
        latitude: "纬度",
        longitude: "经度",
        clearLocation: "清除位置",
        nowFormat: "当前：%@",
        fluxWarning: "f.lux 正在运行，它会修改同一份屏幕颜色，两者会互相覆盖。请退出 f.lux 后再使用此滤镜。",
        scheduleOptions: "日程")

    static let zhTW = DisplayColorFeatureStrings(
        title: "螢幕色彩",
        hubDescription: "依日出日落或固定設定，讓所有螢幕變暖或偏向某種顏色",
        enable: "色彩濾鏡",
        enableCaption: "改變所有螢幕的顏色，可與軟體調暗同時使用。",
        modeSun: "日出日落",
        modeManual: "手動",
        phaseDay: "白天",
        phaseSunset: "日落",
        phaseNight: "夜間",
        whiteBalance: "白平衡",
        tint: "偏色",
        tintStrength: "幅度",
        clearTint: "清除偏色",
        sunTimesFormat: "日出 %@ · 日落 %@",
        fallbackTimes: "未設定位置：以 07:00 日出、19:00 日落計算。",
        bedtime: "就寢時間",
        transition: "漸變時長",
        minutesFormat: "%d 分鐘",
        locate: "使用目前位置",
        locating: "正在定位…",
        locationFailed: "無法取得位置。請在系統設定中檢查定位服務，或手動輸入經緯度。",
        latitude: "緯度",
        longitude: "經度",
        clearLocation: "清除位置",
        nowFormat: "目前：%@",
        fluxWarning: "f.lux 正在執行，它會修改同一份螢幕顏色，兩者會互相覆蓋。請結束 f.lux 後再使用此濾鏡。",
        scheduleOptions: "排程")

    static let zhHK = DisplayColorFeatureStrings(
        title: "螢幕色彩",
        hubDescription: "按日出日落或固定設定，令所有螢幕變暖或偏向某種顏色",
        enable: "色彩濾鏡",
        enableCaption: "改變所有螢幕的顏色，可與軟件調暗同時使用。",
        modeSun: "日出日落",
        modeManual: "手動",
        phaseDay: "日間",
        phaseSunset: "日落",
        phaseNight: "夜間",
        whiteBalance: "白平衡",
        tint: "偏色",
        tintStrength: "幅度",
        clearTint: "清除偏色",
        sunTimesFormat: "日出 %@ · 日落 %@",
        fallbackTimes: "未設定位置：以 07:00 日出、19:00 日落計算。",
        bedtime: "就寢時間",
        transition: "漸變時長",
        minutesFormat: "%d 分鐘",
        locate: "使用目前位置",
        locating: "正在定位…",
        locationFailed: "無法取得位置。請在系統設定中檢查定位服務，或手動輸入經緯度。",
        latitude: "緯度",
        longitude: "經度",
        clearLocation: "清除位置",
        nowFormat: "目前：%@",
        fluxWarning: "f.lux 正在執行，它會修改同一份螢幕顏色，兩者會互相覆蓋。請結束 f.lux 後再使用此濾鏡。",
        scheduleOptions: "時間表")
}
