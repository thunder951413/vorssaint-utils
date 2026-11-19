// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Localized strings for the YTools + mac_gesture integration modules:
/// Jianguoyun YTCE2 E2EE Clipboard Cloud Sync, System Dictionary & Spelling,
/// Interactive Path Browser + Safe File Transfer, Large Type (⌘L),
/// Trackpad Multi-Touch Gestures, and Global Chord Key Remaps.
struct YToolsIntegrationStrings {
    // MARK: - Clipboard Cloud Sync (Jianguoyun WebDAV · YTCE2)
    let syncSectionTitle: String
    let syncEnableToggle: String
    let syncCaption: String
    let syncFolderLabel: String
    let syncFolderPlaceholder: String
    let syncPropagateDeletes: String
    let syncPropagateDeletesCaption: String
    let syncConfigureCredentials: String
    let syncUpdateCredentials: String
    let syncNowButton: String
    let syncCredentialsConfigured: String
    let syncCredentialsMissing: String
    let syncModalTitle: String
    let syncAccountLabel: String
    let syncAppPasswordLabel: String
    let syncPassphraseLabel: String
    let syncPassphraseHint: String
    let syncSaveButton: String
    let syncCancelButton: String

    // MARK: - Command Bar YTools Extensions
    let extensionsSectionTitle: String
    let extensionsSectionFooter: String
    let dictionaryToggle: String
    let dictionaryAutoToggle: String
    let spellToggle: String
    let directoryNavToggle: String
    let pinyinFilesToggle: String
    let largeTypeToggle: String

    // MARK: - Command Bar Row Actions & Subtitles
    let actionLargeType: String
    let actionCopyToFolder: String
    let actionMoveToFolder: String
    let actionBufferAdd: String
    let actionBufferCopyAll: String
    let actionBufferClear: String
    let dictionarySubtitlePrefix: String
    let spellSubtitlePrefix: String
    let folderBrowserSubtitle: String

    // MARK: - Trackpad Multi-Touch Gestures & Chord Key Remaps (mac_gesture)
    let gestureCardTitle: String
    let gestureEnableTitle: String
    let gestureEnableCaption: String
    let chordRemapEnableTitle: String
    let chordRemapEnableCaption: String
    let gestureImportLegacyButton: String
    let gestureResetPresetsButton: String
    let gestureAddRuleButton: String
    let chordAddRuleButton: String

    static func localized(_ language: AppLanguage) -> YToolsIntegrationStrings {
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

enum YToolsStrings {
    private static var current: YToolsIntegrationStrings {
        YToolsIntegrationStrings.localized(L10n.shared.language)
    }

    static var syncSectionTitle: String { current.syncSectionTitle }
    static var syncEnableToggle: String { current.syncEnableToggle }
    static var syncCaption: String { current.syncCaption }
    static var syncFolderLabel: String { current.syncFolderLabel }
    static var syncFolderPlaceholder: String { current.syncFolderPlaceholder }
    static var syncPropagateDeletes: String { current.syncPropagateDeletes }
    static var syncPropagateDeletesCaption: String { current.syncPropagateDeletesCaption }
    static var syncConfigureCredentials: String { current.syncConfigureCredentials }
    static var syncUpdateCredentials: String { current.syncUpdateCredentials }
    static var syncNowButton: String { current.syncNowButton }
    static var syncCredentialsConfigured: String { current.syncCredentialsConfigured }
    static var syncCredentialsMissing: String { current.syncCredentialsMissing }
    static var syncModalTitle: String { current.syncModalTitle }
    static var syncAccountLabel: String { current.syncAccountLabel }
    static var syncAppPasswordLabel: String { current.syncAppPasswordLabel }
    static var syncPassphraseLabel: String { current.syncPassphraseLabel }
    static var syncPassphraseHint: String { current.syncPassphraseHint }
    static var syncSaveButton: String { current.syncSaveButton }
    static var syncCancelButton: String { current.syncCancelButton }

    static var extensionsSectionTitle: String { current.extensionsSectionTitle }
    static var extensionsSectionFooter: String { current.extensionsSectionFooter }
    static var dictionaryToggle: String { current.dictionaryToggle }
    static var dictionaryAutoToggle: String { current.dictionaryAutoToggle }
    static var spellToggle: String { current.spellToggle }
    static var directoryNavToggle: String { current.directoryNavToggle }
    static var pinyinFilesToggle: String { current.pinyinFilesToggle }
    static var largeTypeToggle: String { current.largeTypeToggle }

    static var actionLargeType: String { current.actionLargeType }
    static var actionCopyToFolder: String { current.actionCopyToFolder }
    static var actionMoveToFolder: String { current.actionMoveToFolder }
    static var actionBufferAdd: String { current.actionBufferAdd }
    static var actionBufferCopyAll: String { current.actionBufferCopyAll }
    static var actionBufferClear: String { current.actionBufferClear }
    static var dictionarySubtitlePrefix: String { current.dictionarySubtitlePrefix }
    static var spellSubtitlePrefix: String { current.spellSubtitlePrefix }
    static var folderBrowserSubtitle: String { current.folderBrowserSubtitle }

    static var gestureCardTitle: String { current.gestureCardTitle }
    static var gestureEnableTitle: String { current.gestureEnableTitle }
    static var gestureEnableCaption: String { current.gestureEnableCaption }
    static var chordRemapEnableTitle: String { current.chordRemapEnableTitle }
    static var chordRemapEnableCaption: String { current.chordRemapEnableCaption }
    static var gestureImportLegacyButton: String { current.gestureImportLegacyButton }
    static var gestureResetPresetsButton: String { current.gestureResetPresetsButton }
    static var gestureAddRuleButton: String { current.gestureAddRuleButton }
    static var chordAddRuleButton: String { current.chordAddRuleButton }
}

extension YToolsIntegrationStrings {
    static let enUS = YToolsIntegrationStrings(
        syncSectionTitle: "Cloud Sync (Jianguoyun WebDAV · E2EE)",
        syncEnableToggle: "Sync clipboard across devices",
        syncCaption: "End-to-end encrypted with PBKDF2-SHA256 (600,000 rounds) and AES-256-GCM using the YTCE2 wire format shared with YTools for Windows. Unchanged 4 KB device heads are polled every 15 minutes without downloading ciphertext.",
        syncFolderLabel: "Remote WebDAV folder",
        syncFolderPlaceholder: "YTools",
        syncPropagateDeletes: "Propagate item deletions to other synced devices",
        syncPropagateDeletesCaption: "Writes encrypted tombstones so clearing or deleting an entry removes it on paired Windows and Mac clients.",
        syncConfigureCredentials: "Configure Jianguoyun Credentials…",
        syncUpdateCredentials: "Update Credentials…",
        syncNowButton: "Sync Now",
        syncCredentialsConfigured: "Keychain vault ready",
        syncCredentialsMissing: "Credentials required",
        syncModalTitle: "Jianguoyun WebDAV & E2EE Key",
        syncAccountLabel: "Jianguoyun account email",
        syncAppPasswordLabel: "WebDAV app password",
        syncPassphraseLabel: "End-to-end sync passphrase (12+ characters)",
        syncPassphraseHint: "Must match the exact passphrase set in YTools on your Windows PC. Stored only in your macOS Keychain-protected local vault, never exported in Settings backups.",
        syncSaveButton: "Save to Vault",
        syncCancelButton: "Cancel",
        extensionsSectionTitle: "YTools Extensions",
        extensionsSectionFooter: "Offline dictionary, spelling, interactive path navigation, atomic no-overwrite file transfer, Pinyin file matching, and Large Type.",
        dictionaryToggle: "System Dictionary lookup (define / dict)",
        dictionaryAutoToggle: "Automatically define single English words without a prefix",
        spellToggle: "English spelling suggestions (spell)",
        directoryNavToggle: "Interactive folder navigation (/ and ~) & safe copy/move",
        pinyinFilesToggle: "Match Chinese Pinyin & initials in file and clipboard search",
        largeTypeToggle: "Large Type banner (⌘L on any row)",
        actionLargeType: "Show in Large Type",
        actionCopyToFolder: "Safe Copy to Folder…",
        actionMoveToFolder: "Safe Move to Folder…",
        actionBufferAdd: "Add to File Buffer",
        actionBufferCopyAll: "Copy Buffered Files Here…",
        actionBufferClear: "Clear File Buffer",
        dictionarySubtitlePrefix: "Dictionary",
        spellSubtitlePrefix: "Spelling",
        folderBrowserSubtitle: "Folder Browser · Return or Tab to open",
        gestureCardTitle: "Trackpad Multi-Touch Gestures & Keyboard Automation",
        gestureEnableTitle: "Multi-finger swipe & pinch gestures (2–5 fingers)",
        gestureEnableCaption: "Maps 2–5 finger swipes and 4–5 finger pinches/spreads to shortcuts, URLs, apps, or scripts with palm & misfire rejection.",
        chordRemapEnableTitle: "Global keyboard hotkeys & clean chord remaps",
        chordRemapEnableCaption: "Intercepts key chords (keyDown/keyUp, repeat, per-app scope) and runs multi-step actions without modifier leak.",
        gestureImportLegacyButton: "Import ~/.gesture/config.json",
        gestureResetPresetsButton: "Reset Presets",
        gestureAddRuleButton: "Add Gesture",
        chordAddRuleButton: "Add Key Remap"
    )

    static let zhHans = YToolsIntegrationStrings(
        syncSectionTitle: "云同步（坚果云 WebDAV · 端到端加密）",
        syncEnableToggle: "跨设备同步剪贴板",
        syncCaption: "使用 PBKDF2-SHA256（600,000 次迭代）与 AES-256-GCM 端到端加密，兼容 YTools Windows 版 YTCE2 协议格式。每 15 分钟轮询 4 KB 设备摘要头，无变更时不下载密文。",
        syncFolderLabel: "远程 WebDAV 目录",
        syncFolderPlaceholder: "YTools",
        syncPropagateDeletes: "将删除操作同步到其他已配对设备",
        syncPropagateDeletesCaption: "写入加密删除标记，清空或删除条目时会在配对的 Windows 与 Mac 客户端同步移除。",
        syncConfigureCredentials: "配置坚果云凭据…",
        syncUpdateCredentials: "更新凭据…",
        syncNowButton: "立即同步",
        syncCredentialsConfigured: "钥匙串保险库已就绪",
        syncCredentialsMissing: "需要配置凭据",
        syncModalTitle: "坚果云 WebDAV 与端到端加密密钥",
        syncAccountLabel: "坚果云账号邮箱",
        syncAppPasswordLabel: "WebDAV 应用密码",
        syncPassphraseLabel: "端到端同步口令（至少 12 个字符）",
        syncPassphraseHint: "必须与 Windows 端 YTools 设置的口令完全一致。仅保存在受 macOS 钥匙串保护的本地保险库中，绝不会随设置备份导出。",
        syncSaveButton: "保存到保险库",
        syncCancelButton: "取消",
        extensionsSectionTitle: "YTools 扩展能力",
        extensionsSectionFooter: "离线词典、拼写建议、交互式路径浏览、原子防覆盖文件传输、拼音文件匹配与大字横幅展示。",
        dictionaryToggle: "系统词典查询（define / dict）",
        dictionaryAutoToggle: "输入单个英文单词时无需前缀自动查词",
        spellToggle: "英文拼写建议（spell）",
        directoryNavToggle: "交互式目录浏览（/ 与 ~）及安全复制/移动",
        pinyinFilesToggle: "在文件与剪贴板搜索中支持中文拼音及首字母匹配",
        largeTypeToggle: "大字横幅展示（任意行按 ⌘L）",
        actionLargeType: "以大字横幅显示",
        actionCopyToFolder: "安全复制到文件夹…",
        actionMoveToFolder: "安全移动到文件夹…",
        actionBufferAdd: "加入文件暂存区",
        actionBufferCopyAll: "将暂存文件复制到此处…",
        actionBufferClear: "清空文件暂存区",
        dictionarySubtitlePrefix: "词典",
        spellSubtitlePrefix: "拼写",
        folderBrowserSubtitle: "目录浏览器 · 按 Return 或 Tab 打开",
        gestureCardTitle: "触控板多指手势与键盘自动化",
        gestureEnableTitle: "多指滑动与捏合手势（2–5 指）",
        gestureEnableCaption: "将 2–5 指滑动和 4–5 指捏合/张开映射为快捷键、网址、应用或脚本，内置防掌误触校验。",
        chordRemapEnableTitle: "全局键盘热键与无泄漏组合键重映射",
        chordRemapEnableCaption: "拦截组合键（支持按下/松开、连发、按应用限定范围）并执行多步动作，避免修饰键泄漏。",
        gestureImportLegacyButton: "导入 ~/.gesture/config.json",
        gestureResetPresetsButton: "恢复默认规则",
        gestureAddRuleButton: "添加手势",
        chordAddRuleButton: "添加按键重映射"
    )

    static let zhTW = YToolsIntegrationStrings(
        syncSectionTitle: "雲端同步（堅果雲 WebDAV · 端對端加密）",
        syncEnableToggle: "跨裝置同步剪貼簿",
        syncCaption: "使用 PBKDF2-SHA256（600,000 次迭代）與 AES-256-GCM 端對端加密，相容 YTools Windows 版 YTCE2 協定格式。每 15 分鐘輪詢 4 KB 裝置摘要頭，無變更時不下載密文。",
        syncFolderLabel: "遠端 WebDAV 資料夾",
        syncFolderPlaceholder: "YTools",
        syncPropagateDeletes: "將刪除操作同步至其他已配對裝置",
        syncPropagateDeletesCaption: "寫入加密刪除標記，清除或刪除項目時會在配對的 Windows 與 Mac 用戶端同步移除。",
        syncConfigureCredentials: "設定堅果雲憑證…",
        syncUpdateCredentials: "更新憑證…",
        syncNowButton: "立即同步",
        syncCredentialsConfigured: "鑰匙圈保險庫已就緒",
        syncCredentialsMissing: "需要設定憑證",
        syncModalTitle: "堅果雲 WebDAV 與端對端加密金鑰",
        syncAccountLabel: "堅果雲帳號電子郵件",
        syncAppPasswordLabel: "WebDAV 應用程式密碼",
        syncPassphraseLabel: "端對端同步密語（至少 12 個字元）",
        syncPassphraseHint: "必須與 Windows 端 YTools 設定的密語完全一致。僅儲存在受 macOS 鑰匙圈保護的本機保險庫中，絕不隨設定備份匯出。",
        syncSaveButton: "儲存至保險庫",
        syncCancelButton: "取消",
        extensionsSectionTitle: "YTools 擴充功能",
        extensionsSectionFooter: "離線辭典、拼字建議、互動式路徑瀏覽、原子防覆蓋檔案傳輸、拼音檔案比對與大字橫幅顯示。",
        dictionaryToggle: "系統辭典查詢（define / dict）",
        dictionaryAutoToggle: "輸入單一英文單字時無需前綴自動查詞",
        spellToggle: "英文拼字建議（spell）",
        directoryNavToggle: "互動式資料夾瀏覽（/ 與 ~）與安全複製/移動",
        pinyinFilesToggle: "在檔案與剪貼簿搜尋中支援中文拼音及首字母比對",
        largeTypeToggle: "大字橫幅顯示（任一列按 ⌘L）",
        actionLargeType: "以大字橫幅顯示",
        actionCopyToFolder: "安全複製到資料夾…",
        actionMoveToFolder: "安全移動到資料夾…",
        actionBufferAdd: "加入檔案暫存區",
        actionBufferCopyAll: "將暫存檔案複製到此處…",
        actionBufferClear: "清除檔案暫存區",
        dictionarySubtitlePrefix: "辭典",
        spellSubtitlePrefix: "拼字",
        folderBrowserSubtitle: "資料夾瀏覽器 · 按 Return 或 Tab 開啟",
        gestureCardTitle: "觸控式軌跡板多指手勢與鍵盤自動化",
        gestureEnableTitle: "多指滑動與捏合手勢（2–5 指）",
        gestureEnableCaption: "將 2–5 指滑動與 4–5 指捏合/張開對應至快速鍵、網址、應用程式或指令碼，內建防掌誤觸過濾。",
        chordRemapEnableTitle: "全域鍵盤快速鍵與無洩漏組合鍵重對應",
        chordRemapEnableCaption: "攔截組合鍵（支援按下/放開、連發、依應用程式限定範圍）並執行多步動作，避免修飾鍵洩漏。",
        gestureImportLegacyButton: "匯入 ~/.gesture/config.json",
        gestureResetPresetsButton: "重設預設規則",
        gestureAddRuleButton: "新增手勢",
        chordAddRuleButton: "新增按鍵重對應"
    )

    static let zhHK = YToolsIntegrationStrings(
        syncSectionTitle: "雲端同步（堅果雲 WebDAV · 端對端加密）",
        syncEnableToggle: "跨裝置同步剪貼簿",
        syncCaption: "使用 PBKDF2-SHA256（600,000 次迭代）與 AES-256-GCM 端對端加密，相容 YTools Windows 版 YTCE2 協定格式。每 15 分鐘輪詢 4 KB 裝置摘要頭，無變更時不會下載密文。",
        syncFolderLabel: "遠端 WebDAV 資料夾",
        syncFolderPlaceholder: "YTools",
        syncPropagateDeletes: "將刪除操作同步至其他已配對裝置",
        syncPropagateDeletesCaption: "寫入加密刪除標記，清除或刪除項目時會在配對的 Windows 與 Mac 用戶端同步移除。",
        syncConfigureCredentials: "設定堅果雲憑證…",
        syncUpdateCredentials: "更新憑證…",
        syncNowButton: "立即同步",
        syncCredentialsConfigured: "鑰匙圈保險庫已就緒",
        syncCredentialsMissing: "需要設定憑證",
        syncModalTitle: "堅果雲 WebDAV 與端對端加密密鑰",
        syncAccountLabel: "堅果雲帳戶電郵",
        syncAppPasswordLabel: "WebDAV 應用程式密碼",
        syncPassphraseLabel: "端對端同步密語（至少 12 個字元）",
        syncPassphraseHint: "必須與 Windows 端 YTools 設定的密語完全一致。只會儲存在受 macOS 鑰匙圈保護的本機保險庫中，絕不隨設定備份匯出。",
        syncSaveButton: "儲存至保險庫",
        syncCancelButton: "取消",
        extensionsSectionTitle: "YTools 擴充功能",
        extensionsSectionFooter: "離線詞典、拼字建議、互動式路徑瀏覽、原子防覆蓋檔案傳輸、拼音檔案配對與大字橫幅顯示。",
        dictionaryToggle: "系統詞典查詢（define / dict）",
        dictionaryAutoToggle: "輸入單一英文生字時無需前綴自動查詞",
        spellToggle: "英文拼字建議（spell）",
        directoryNavToggle: "互動式資料夾瀏覽（/ 與 ~）及安全複製/移動",
        pinyinFilesToggle: "在檔案與剪貼簿搜尋中支援中文拼音及首字母配對",
        largeTypeToggle: "大字橫幅顯示（任何一列按 ⌘L）",
        actionLargeType: "以大字橫幅顯示",
        actionCopyToFolder: "安全複製到資料夾…",
        actionMoveToFolder: "安全移動到資料夾…",
        actionBufferAdd: "加入檔案暫存區",
        actionBufferCopyAll: "將暫存檔案複製到此處…",
        actionBufferClear: "清空檔案暫存區",
        dictionarySubtitlePrefix: "詞典",
        spellSubtitlePrefix: "拼字",
        folderBrowserSubtitle: "資料夾瀏覽器 · 按 Return 或 Tab 開啟",
        gestureCardTitle: "觸控板多指手勢與鍵盤自動化",
        gestureEnableTitle: "多指滑動與捏合手勢（2–5 指）",
        gestureEnableCaption: "將 2–5 指滑動與 4–5 指捏合/張開對應至快捷鍵、網址、應用程式或指令碼，內置防誤觸過濾。",
        chordRemapEnableTitle: "全域鍵盤快捷鍵與無洩漏組合鍵重對應",
        chordRemapEnableCaption: "攔截組合鍵（支援按下/放開、連發、按應用程式限定範圍）並執行多步動作，避免修飾鍵洩漏。",
        gestureImportLegacyButton: "匯入 ~/.gesture/config.json",
        gestureResetPresetsButton: "重設預設規則",
        gestureAddRuleButton: "新增手勢",
        chordAddRuleButton: "新增按鍵重對應"
    )

    static let ptBR = YToolsIntegrationStrings(
        syncSectionTitle: "Sincronização na nuvem (Jianguoyun WebDAV · E2EE)",
        syncEnableToggle: "Sincronizar área de transferência entre dispositivos",
        syncCaption: "Criptografado de ponta a ponta com PBKDF2-SHA256 (600.000 rodadas) e AES-256-GCM no formato YTCE2 compatível com o YTools para Windows. Cabeçalhos de 4 KB sem alterações são verificados a cada 15 minutos sem baixar texto cifrado.",
        syncFolderLabel: "Pasta WebDAV remota",
        syncFolderPlaceholder: "YTools",
        syncPropagateDeletes: "Propagar exclusões para outros dispositivos sincronizados",
        syncPropagateDeletesCaption: "Grava marcadores criptografados para que limpar ou excluir um item o remova nos clientes Windows e Mac pareados.",
        syncConfigureCredentials: "Configurar credenciais do Jianguoyun…",
        syncUpdateCredentials: "Atualizar credenciais…",
        syncNowButton: "Sincronizar agora",
        syncCredentialsConfigured: "Cofre do Acesso às Chaves pronto",
        syncCredentialsMissing: "Credenciais necessárias",
        syncModalTitle: "Jianguoyun WebDAV e chave E2EE",
        syncAccountLabel: "E-mail da conta Jianguoyun",
        syncAppPasswordLabel: "Senha de app WebDAV",
        syncPassphraseLabel: "Frase secreta de sincronização E2EE (12+ caracteres)",
        syncPassphraseHint: "Deve corresponder exatamente à frase definida no YTools no seu PC Windows. Armazenada apenas no cofre local protegido pelo Acesso às Chaves do macOS, nunca exportada em backups.",
        syncSaveButton: "Salvar no cofre",
        syncCancelButton: "Cancelar",
        extensionsSectionTitle: "Extensões YTools",
        extensionsSectionFooter: "Dicionário offline, ortografia, navegação interativa de pastas, transferência atômica sem sobrescrita, busca por Pinyin e Texto Grande.",
        dictionaryToggle: "Consulta ao Dicionário do sistema (define / dict)",
        dictionaryAutoToggle: "Definir automaticamente palavras únicas em inglês sem prefixo",
        spellToggle: "Sugestões de ortografia em inglês (spell)",
        directoryNavToggle: "Navegação interativa de pastas (/ e ~) e cópia/movimentação segura",
        pinyinFilesToggle: "Corresponder Pinyin e iniciais chinesas na busca de arquivos e área de transferência",
        largeTypeToggle: "Faixa de Texto Grande (⌘L em qualquer linha)",
        actionLargeType: "Mostrar em Texto Grande",
        actionCopyToFolder: "Copiar com segurança para pasta…",
        actionMoveToFolder: "Mover com segurança para pasta…",
        actionBufferAdd: "Adicionar ao buffer de arquivos",
        actionBufferCopyAll: "Copiar arquivos do buffer aqui…",
        actionBufferClear: "Limpar buffer de arquivos",
        dictionarySubtitlePrefix: "Dicionário",
        spellSubtitlePrefix: "Ortografia",
        folderBrowserSubtitle: "Navegador de pastas · Return ou Tab para abrir",
        gestureCardTitle: "Gestos multitoque do trackpad e automação de teclado",
        gestureEnableTitle: "Gestos de deslizar e pinçar com vários dedos (2–5 dedos)",
        gestureEnableCaption: "Mapeia deslizes de 2–5 dedos e pinças de 4–5 dedos para atalhos, URLs, apps ou scripts com rejeição de palma e toques acidentais.",
        chordRemapEnableTitle: "Atalhos globais de teclado e remapeamento limpo de acordes",
        chordRemapEnableCaption: "Intercepta combinações de teclas (keyDown/keyUp, repetição, escopo por app) e executa ações em várias etapas sem vazamento de modificadores.",
        gestureImportLegacyButton: "Importar ~/.gesture/config.json",
        gestureResetPresetsButton: "Restaurar padrões",
        gestureAddRuleButton: "Adicionar gesto",
        chordAddRuleButton: "Adicionar remapeamento"
    )

    static let es = YToolsIntegrationStrings(
        syncSectionTitle: "Sincronización en la nube (Jianguoyun WebDAV · E2EE)",
        syncEnableToggle: "Sincronizar portapapeles entre dispositivos",
        syncCaption: "Cifrado de extremo a extremo con PBKDF2-SHA256 (600.000 rondas) y AES-256-GCM en el formato YTCE2 compatible con YTools para Windows. Las cabeceras de 4 KB sin cambios se consultan cada 15 minutos sin descargar texto cifrado.",
        syncFolderLabel: "Carpeta WebDAV remota",
        syncFolderPlaceholder: "YTools",
        syncPropagateDeletes: "Propagar eliminaciones a otros dispositivos sincronizados",
        syncPropagateDeletesCaption: "Escribe marcadores cifrados para que borrar o limpiar una entrada la elimine en los clientes Windows y Mac vinculados.",
        syncConfigureCredentials: "Configurar credenciales de Jianguoyun…",
        syncUpdateCredentials: "Actualizar credenciales…",
        syncNowButton: "Sincronizar ahora",
        syncCredentialsConfigured: "Bóveda de Llaveros lista",
        syncCredentialsMissing: "Se requieren credenciales",
        syncModalTitle: "Jianguoyun WebDAV y clave E2EE",
        syncAccountLabel: "Correo de la cuenta Jianguoyun",
        syncAppPasswordLabel: "Contraseña de app WebDAV",
        syncPassphraseLabel: "Frase secreta de sincronización E2EE (12+ caracteres)",
        syncPassphraseHint: "Debe coincidir exactamente con la frase configurada en YTools en tu PC Windows. Se guarda solo en tu bóveda local protegida por el Llavero de macOS, nunca se exporta en copias de seguridad.",
        syncSaveButton: "Guardar en la bóveda",
        syncCancelButton: "Cancelar",
        extensionsSectionTitle: "Extensiones YTools",
        extensionsSectionFooter: "Diccionario sin conexión, ortografía, navegación interactiva de rutas, transferencia atómica sin sobrescritura, coincidencia Pinyin y Texto Grande.",
        dictionaryToggle: "Consulta al Diccionario del sistema (define / dict)",
        dictionaryAutoToggle: "Definir automáticamente palabras sueltas en inglés sin prefijo",
        spellToggle: "Sugerencias de ortografía en inglés (spell)",
        directoryNavToggle: "Navegación interactiva de carpetas (/ y ~) y copia/movimiento seguro",
        pinyinFilesToggle: "Coincidir Pinyin e iniciales chinas al buscar archivos y portapapeles",
        largeTypeToggle: "Cartel de Texto Grande (⌘L en cualquier fila)",
        actionLargeType: "Mostrar en Texto Grande",
        actionCopyToFolder: "Copiar con seguridad a carpeta…",
        actionMoveToFolder: "Mover con seguridad a carpeta…",
        actionBufferAdd: "Añadir al búfer de archivos",
        actionBufferCopyAll: "Copiar archivos del búfer aquí…",
        actionBufferClear: "Vaciar búfer de archivos",
        dictionarySubtitlePrefix: "Diccionario",
        spellSubtitlePrefix: "Ortografía",
        folderBrowserSubtitle: "Explorador de carpetas · Return o Tab para abrir",
        gestureCardTitle: "Gestos multitáctiles del trackpad y automatización de teclado",
        gestureEnableTitle: "Gestos de deslizamiento y pellizco (2–5 dedos)",
        gestureEnableCaption: "Asigna deslizamientos de 2–5 dedos y pellizcos de 4–5 dedos a atajos, URLs, apps o scripts con rechazo de palma y falsos toques.",
        chordRemapEnableTitle: "Atajos globales de teclado y reasignación limpia de acordes",
        chordRemapEnableCaption: "Intercepta combinaciones de teclas (keyDown/keyUp, repetición, ámbito por app) y ejecuta acciones en varios pasos sin fugas de modificadores.",
        gestureImportLegacyButton: "Importar ~/.gesture/config.json",
        gestureResetPresetsButton: "Restablecer ajustes",
        gestureAddRuleButton: "Añadir gesto",
        chordAddRuleButton: "Añadir reasignación"
    )

    static let de = YToolsIntegrationStrings(
        syncSectionTitle: "Cloud-Synchronisierung (Jianguoyun WebDAV · E2EE)",
        syncEnableToggle: "Zwischenablage geräteübergreifend synchronisieren",
        syncCaption: "Ende-zu-Ende-verschlüsselt mit PBKDF2-SHA256 (600.000 Runden) und AES-256-GCM im YTCE2-Format für YTools unter Windows. Unveränderte 4-KB-Geräteköpfe werden alle 15 Minuten abgefragt, ohne Chiffretext herunterzuladen.",
        syncFolderLabel: "Entfernter WebDAV-Ordner",
        syncFolderPlaceholder: "YTools",
        syncPropagateDeletes: "Löschungen auf andere synchronisierte Geräte übertragen",
        syncPropagateDeletesCaption: "Schreibt verschlüsselte Löschmarkierungen, damit entfernte Einträge auch auf gekoppelten Windows- und Mac-Geräten gelöscht werden.",
        syncConfigureCredentials: "Jianguoyun-Zugangsdaten konfigurieren…",
        syncUpdateCredentials: "Zugangsdaten aktualisieren…",
        syncNowButton: "Jetzt synchronisieren",
        syncCredentialsConfigured: "Schlüsselbund-Tresor bereit",
        syncCredentialsMissing: "Zugangsdaten erforderlich",
        syncModalTitle: "Jianguoyun WebDAV & E2EE-Schlüssel",
        syncAccountLabel: "Jianguoyun-Konto-E-Mail",
        syncAppPasswordLabel: "WebDAV-App-Passwort",
        syncPassphraseLabel: "E2EE-Synchronisierungs-Passphrase (12+ Zeichen)",
        syncPassphraseHint: "Muss exakt mit der Passphrase in YTools auf Ihrem Windows-PC übereinstimmen. Wird nur lokal im macOS-Schlüsselbund-Tresor gespeichert und nie in Einstellungs-Backups exportiert.",
        syncSaveButton: "Im Tresor speichern",
        syncCancelButton: "Abbrechen",
        extensionsSectionTitle: "YTools-Erweiterungen",
        extensionsSectionFooter: "Offline-Wörterbuch, Rechtschreibung, interaktive Pfadnavigation, atomare Dateiübertragung ohne Überschreiben, Pinyin-Suche und Großschrift.",
        dictionaryToggle: "System-Wörterbuchsuche (define / dict)",
        dictionaryAutoToggle: "Einzelne englische Wörter automatisch ohne Präfix nachschlagen",
        spellToggle: "Englische Rechtschreibvorschläge (spell)",
        directoryNavToggle: "Interaktive Ordnernavigation (/ und ~) & sicheres Kopieren/Verschieben",
        pinyinFilesToggle: "Chinesisches Pinyin & Anfangsbuchstaben in Datei- und Zwischenablagesuche abgleichen",
        largeTypeToggle: "Großschrift-Banner (⌘L in jeder Zeile)",
        actionLargeType: "In Großschrift anzeigen",
        actionCopyToFolder: "Sicher in Ordner kopieren…",
        actionMoveToFolder: "Sicher in Ordner verschieben…",
        actionBufferAdd: "Zum Dateipuffer hinzufügen",
        actionBufferCopyAll: "Gepufferte Dateien hierher kopieren…",
        actionBufferClear: "Dateipuffer leeren",
        dictionarySubtitlePrefix: "Wörterbuch",
        spellSubtitlePrefix: "Rechtschreibung",
        folderBrowserSubtitle: "Ordnerbrowser · Return oder Tab zum Öffnen",
        gestureCardTitle: "Trackpad-Multitouch-Gesten & Tastaturautomatisierung",
        gestureEnableTitle: "Mehrfinger-Wisch- und Pinch-Gesten (2–5 Finger)",
        gestureEnableCaption: "Ordnet 2–5-Finger-Wischen und 4–5-Finger-Pinch-Gesten Kurzbefehlen, URLs, Apps oder Skripten zu, mit Handballen- und Fehlauslösungsschutz.",
        chordRemapEnableTitle: "Globale Tastaturkurzbefehle & saubere Tasten-Neubelegung",
        chordRemapEnableCaption: "Fängt Tastenkombinationen ab (keyDown/keyUp, Wiederholung, App-Bereich) und führt mehrstufige Aktionen ohne Modifikator-Leck aus.",
        gestureImportLegacyButton: "~/.gesture/config.json importieren",
        gestureResetPresetsButton: "Vorlagen zurücksetzen",
        gestureAddRuleButton: "Geste hinzufügen",
        chordAddRuleButton: "Neubelegung hinzufügen"
    )

    static let fr = YToolsIntegrationStrings(
        syncSectionTitle: "Synchronisation cloud (Jianguoyun WebDAV · E2EE)",
        syncEnableToggle: "Synchroniser le presse-papiers entre appareils",
        syncCaption: "Chiffré de bout en bout avec PBKDF2-SHA256 (600 000 itérations) et AES-256-GCM au format YTCE2 partagé avec YTools pour Windows. Les en-têtes de 4 Ko inchangés sont vérifiés toutes les 15 minutes sans télécharger le texte chiffré.",
        syncFolderLabel: "Dossier WebDAV distant",
        syncFolderPlaceholder: "YTools",
        syncPropagateDeletes: "Propager les suppressions aux autres appareils synchronisés",
        syncPropagateDeletesCaption: "Écrit des marqueurs chiffrés afin que la suppression d’un élément le retire sur les clients Windows et Mac associés.",
        syncConfigureCredentials: "Configurer les identifiants Jianguoyun…",
        syncUpdateCredentials: "Mettre à jour les identifiants…",
        syncNowButton: "Synchroniser maintenant",
        syncCredentialsConfigured: "Coffre Trousseau prêt",
        syncCredentialsMissing: "Identifiants requis",
        syncModalTitle: "Jianguoyun WebDAV et clé E2EE",
        syncAccountLabel: "E-mail du compte Jianguoyun",
        syncAppPasswordLabel: "Mot de passe d’application WebDAV",
        syncPassphraseLabel: "Phrase secrète de synchronisation E2EE (12+ caractères)",
        syncPassphraseHint: "Doit correspondre exactement à la phrase définie dans YTools sur votre PC Windows. Stockée uniquement dans votre coffre local protégé par le Trousseau macOS, jamais exportée dans les sauvegardes.",
        syncSaveButton: "Enregistrer dans le coffre",
        syncCancelButton: "Annuler",
        extensionsSectionTitle: "Extensions YTools",
        extensionsSectionFooter: "Dictionnaire hors ligne, orthographe, navigation interactive dans les dossiers, transfert atomique sans écrasement, recherche Pinyin et Grand Texte.",
        dictionaryToggle: "Recherche dans le Dictionnaire système (define / dict)",
        dictionaryAutoToggle: "Définir automatiquement un mot anglais seul sans préfixe",
        spellToggle: "Suggestions orthographiques anglaises (spell)",
        directoryNavToggle: "Navigation interactive des dossiers (/ et ~) et copie/déplacement sûr",
        pinyinFilesToggle: "Correspondance Pinyin et initiales chinoises dans la recherche de fichiers et presse-papiers",
        largeTypeToggle: "Bannière Grand Texte (⌘L sur toute ligne)",
        actionLargeType: "Afficher en Grand Texte",
        actionCopyToFolder: "Copier en toute sécurité vers le dossier…",
        actionMoveToFolder: "Déplacer en toute sécurité vers le dossier…",
        actionBufferAdd: "Ajouter au tampon de fichiers",
        actionBufferCopyAll: "Copier les fichiers en tampon ici…",
        actionBufferClear: "Vider le tampon de fichiers",
        dictionarySubtitlePrefix: "Dictionnaire",
        spellSubtitlePrefix: "Orthographe",
        folderBrowserSubtitle: "Explorateur de dossiers · Entrée ou Tab pour ouvrir",
        gestureCardTitle: "Gestes multi-touch du trackpad et automatisation clavier",
        gestureEnableTitle: "Gestes de balayage et pincement (2–5 doigts)",
        gestureEnableCaption: "Associe les balayages à 2–5 doigts et pincements à 4–5 doigts à des raccourcis, URL, apps ou scripts avec rejet de la paume et des faux déclenchements.",
        chordRemapEnableTitle: "Raccourcis clavier globaux et remappage propre d’accords",
        chordRemapEnableCaption: "Intercepte les combinaisons de touches (keyDown/keyUp, répétition, portée par app) et exécute des actions multi-étapes sans fuite de modificateurs.",
        gestureImportLegacyButton: "Importer ~/.gesture/config.json",
        gestureResetPresetsButton: "Réinitialiser les préréglages",
        gestureAddRuleButton: "Ajouter un geste",
        chordAddRuleButton: "Ajouter un remappage"
    )

    static let it = YToolsIntegrationStrings(
        syncSectionTitle: "Sincronizzazione cloud (Jianguoyun WebDAV · E2EE)",
        syncEnableToggle: "Sincronizza appunti tra dispositivi",
        syncCaption: "Crittografato end-to-end con PBKDF2-SHA256 (600.000 round) e AES-256-GCM nel formato YTCE2 compatibile con YTools per Windows. Le intestazioni da 4 KB invariate vengono controllate ogni 15 minuti senza scaricare testo cifrato.",
        syncFolderLabel: "Cartella WebDAV remota",
        syncFolderPlaceholder: "YTools",
        syncPropagateDeletes: "Propaga le eliminazioni agli altri dispositivi sincronizzati",
        syncPropagateDeletesCaption: "Scrive marcatori cifrati affinché la rimozione di un elemento lo elimini anche sui client Windows e Mac associati.",
        syncConfigureCredentials: "Configura credenziali Jianguoyun…",
        syncUpdateCredentials: "Aggiorna credenziali…",
        syncNowButton: "Sincronizza ora",
        syncCredentialsConfigured: "Archivio Portachiavi pronto",
        syncCredentialsMissing: "Credenziali richieste",
        syncModalTitle: "Jianguoyun WebDAV e chiave E2EE",
        syncAccountLabel: "Email dell’account Jianguoyun",
        syncAppPasswordLabel: "Password app WebDAV",
        syncPassphraseLabel: "Passphrase di sincronizzazione E2EE (12+ caratteri)",
        syncPassphraseHint: "Deve corrispondere esattamente alla passphrase impostata in YTools sul PC Windows. Salvata solo nell’archivio locale protetto dal Portachiavi macOS, mai esportata nei backup.",
        syncSaveButton: "Salva nell’archivio",
        syncCancelButton: "Annulla",
        extensionsSectionTitle: "Estensioni YTools",
        extensionsSectionFooter: "Dizionario offline, ortografia, navigazione interattiva dei percorsi, trasferimento atomico senza sovrascrittura, corrispondenza Pinyin e Testo Grande.",
        dictionaryToggle: "Ricerca Dizionario di sistema (define / dict)",
        dictionaryAutoToggle: "Definisci automaticamente singole parole inglesi senza prefisso",
        spellToggle: "Suggerimenti ortografici inglesi (spell)",
        directoryNavToggle: "Navigazione interattiva cartelle (/ e ~) e copia/spostamento sicuro",
        pinyinFilesToggle: "Corrispondenza Pinyin e iniziali cinesi nella ricerca di file e appunti",
        largeTypeToggle: "Banner Testo Grande (⌘L su qualsiasi riga)",
        actionLargeType: "Mostra in Testo Grande",
        actionCopyToFolder: "Copia in modo sicuro nella cartella…",
        actionMoveToFolder: "Sposta in modo sicuro nella cartella…",
        actionBufferAdd: "Aggiungi al buffer file",
        actionBufferCopyAll: "Copia qui i file nel buffer…",
        actionBufferClear: "Svuota buffer file",
        dictionarySubtitlePrefix: "Dizionario",
        spellSubtitlePrefix: "Ortografia",
        folderBrowserSubtitle: "Browser cartelle · Invio o Tab per aprire",
        gestureCardTitle: "Gesti multi-touch del trackpad e automazione tastiera",
        gestureEnableTitle: "Gesti di scorrimento e pizzico (2–5 dita)",
        gestureEnableCaption: "Associa scorrimenti a 2–5 dita e pizzichi a 4–5 dita a scorciatoie, URL, app o script con filtro palmo e tocchi accidentali.",
        chordRemapEnableTitle: "Scorciatoie tastiera globali e rimappatura pulita di accordi",
        chordRemapEnableCaption: "Intercetta combinazioni di tasti (keyDown/keyUp, ripetizione, ambito per app) ed esegue azioni in più passaggi senza perdita di modificatori.",
        gestureImportLegacyButton: "Importa ~/.gesture/config.json",
        gestureResetPresetsButton: "Ripristina predefiniti",
        gestureAddRuleButton: "Aggiungi gesto",
        chordAddRuleButton: "Aggiungi rimappatura"
    )

    static let ja = YToolsIntegrationStrings(
        syncSectionTitle: "クラウド同期（Jianguoyun WebDAV · E2EE）",
        syncEnableToggle: "デバイス間でクリップボードを同期",
        syncCaption: "PBKDF2-SHA256（600,000 回）と AES-256-GCM によるエンドツーエンド暗号化で、Windows 版 YTools の YTCE2 形式に対応します。変更のない 4 KB ヘッダーは 15 分ごとに確認され、暗号文はダウンロードされません。",
        syncFolderLabel: "リモート WebDAV フォルダ",
        syncFolderPlaceholder: "YTools",
        syncPropagateDeletes: "削除操作を他の同期デバイスに反映",
        syncPropagateDeletesCaption: "暗号化された削除マーカーを書き込み、項目の削除や消去をペアリング済みの Windows・Mac 端末にも反映します。",
        syncConfigureCredentials: "Jianguoyun 認証情報を設定…",
        syncUpdateCredentials: "認証情報を更新…",
        syncNowButton: "今すぐ同期",
        syncCredentialsConfigured: "キーチェーンボールト準備完了",
        syncCredentialsMissing: "認証情報が必要です",
        syncModalTitle: "Jianguoyun WebDAV と E2EE キー",
        syncAccountLabel: "Jianguoyun アカウントメール",
        syncAppPasswordLabel: "WebDAV アプリパスワード",
        syncPassphraseLabel: "エンドツーエンド同期パスフレーズ（12 文字以上）",
        syncPassphraseHint: "Windows PC の YTools で設定したパスフレーズと完全に一致させる必要があります。macOS キーチェーン保護のローカルボールトにのみ保存され、設定バックアップには含まれません。",
        syncSaveButton: "ボールトに保存",
        syncCancelButton: "キャンセル",
        extensionsSectionTitle: "YTools 拡張機能",
        extensionsSectionFooter: "オフライン辞書、スペル候補、対話式パス移動、上書きしない安全なファイル転送、ピンイン検索、ラージタイプ表示。",
        dictionaryToggle: "システム辞書検索（define / dict）",
        dictionaryAutoToggle: "接頭辞なしで英単語 1 語を自動的に辞書検索",
        spellToggle: "英語スペル候補（spell）",
        directoryNavToggle: "対話式フォルダ移動（/ と ~）および安全なコピー/移動",
        pinyinFilesToggle: "ファイル・クリップボード検索で中国語ピンインと頭文字を照合",
        largeTypeToggle: "ラージタイプ表示（任意の行で ⌘L）",
        actionLargeType: "ラージタイプで表示",
        actionCopyToFolder: "フォルダへ安全にコピー…",
        actionMoveToFolder: "フォルダへ安全に移動…",
        actionBufferAdd: "ファイルバッファに追加",
        actionBufferCopyAll: "バッファ内のファイルをここにコピー…",
        actionBufferClear: "ファイルバッファをクリア",
        dictionarySubtitlePrefix: "辞書",
        spellSubtitlePrefix: "スペル",
        folderBrowserSubtitle: "フォルダブラウザ · Return または Tab で開く",
        gestureCardTitle: "トラックパッドマルチタッチジェスチャとキーボード自動化",
        gestureEnableTitle: "マルチフィンガースワイプ・ピンチジェスチャ（2〜5 本指）",
        gestureEnableCaption: "2〜5 本指スワイプや 4〜5 本指ピンチ/スプレッドをショートカット、URL、アプリ、スクリプトに割り当てます（パーム誤操作防止付き）。",
        chordRemapEnableTitle: "グローバルキーボードホットキーとクリーンなリマップ",
        chordRemapEnableCaption: "キーコードの組み合わせ（keyDown/keyUp、リピート、アプリ別範囲）を捕捉し、修飾キー漏れなしで複数ステップを実行します。",
        gestureImportLegacyButton: "~/.gesture/config.json をインポート",
        gestureResetPresetsButton: "プリセットをリセット",
        gestureAddRuleButton: "ジェスチャを追加",
        chordAddRuleButton: "キーリマップを追加"
    )

    static let ko = YToolsIntegrationStrings(
        syncSectionTitle: "클라우드 동기화 (Jianguoyun WebDAV · E2EE)",
        syncEnableToggle: "기기 간 클립보드 동기화",
        syncCaption: "PBKDF2-SHA256(600,000회)과 AES-256-GCM 종단간 암호화를 사용하며 Windows용 YTools의 YTCE2 형식과 호환됩니다. 변경되지 않은 4 KB 헤더는 암호문을 내려받지 않고 15분마다 확인합니다.",
        syncFolderLabel: "원격 WebDAV 폴더",
        syncFolderPlaceholder: "YTools",
        syncPropagateDeletes: "항목 삭제를 다른 동기화 기기에 전파",
        syncPropagateDeletesCaption: "암호화된 삭제 표시를 기록하여 항목을 삭제하거나 비우면 페어링된 Windows 및 Mac 클라이언트에서도 제거됩니다.",
        syncConfigureCredentials: "Jianguoyun 자격 증명 구성…",
        syncUpdateCredentials: "자격 증명 업데이트…",
        syncNowButton: "지금 동기화",
        syncCredentialsConfigured: "키체인 보관함 준비됨",
        syncCredentialsMissing: "자격 증명 필요",
        syncModalTitle: "Jianguoyun WebDAV 및 E2EE 키",
        syncAccountLabel: "Jianguoyun 계정 이메일",
        syncAppPasswordLabel: "WebDAV 앱 비밀번호",
        syncPassphraseLabel: "종단간 동기화 암호문 (12자 이상)",
        syncPassphraseHint: "Windows PC의 YTools에 설정한 암호문과 정확히 일치해야 합니다. macOS 키체인으로 보호되는 로컬 보관함에만 저장되며 설정 백업으로 내보내지지 않습니다.",
        syncSaveButton: "보관함에 저장",
        syncCancelButton: "취소",
        extensionsSectionTitle: "YTools 확장 기능",
        extensionsSectionFooter: "오프라인 사전, 맞춤법 제안, 대화형 경로 탐색, 덮어쓰기 없는 안전한 파일 전송, 병음 파일 검색 및 큰 글씨 표시.",
        dictionaryToggle: "시스템 사전 검색 (define / dict)",
        dictionaryAutoToggle: "접두어 없이 영어 단어 하나를 자동으로 사전 검색",
        spellToggle: "영어 맞춤법 제안 (spell)",
        directoryNavToggle: "대화형 폴더 탐색 (/ 및 ~)과 안전한 복사/이동",
        pinyinFilesToggle: "파일 및 클립보드 검색에서 중국어 병음 및 초성 일치",
        largeTypeToggle: "큰 글씨 배너 (아무 행에서나 ⌘L)",
        actionLargeType: "큰 글씨로 표시",
        actionCopyToFolder: "폴더로 안전하게 복사…",
        actionMoveToFolder: "폴더로 안전하게 이동…",
        actionBufferAdd: "파일 버퍼에 추가",
        actionBufferCopyAll: "버퍼의 파일을 여기로 복사…",
        actionBufferClear: "파일 버퍼 비우기",
        dictionarySubtitlePrefix: "사전",
        spellSubtitlePrefix: "맞춤법",
        folderBrowserSubtitle: "폴더 브라우저 · Return 또는 Tab으로 열기",
        gestureCardTitle: "트랙패드 멀티터치 제스처 및 키보드 자동화",
        gestureEnableTitle: "멀티핑거 스와이프 및 핀치 제스처 (2–5손가락)",
        gestureEnableCaption: "2–5손가락 스와이프와 4–5손가락 핀치/펼치기를 단축키, URL, 앱 또는 스크립트에 매핑하며 손바닥 오작동을 방지합니다.",
        chordRemapEnableTitle: "전역 키보드 단축키 및 깔끔한 조합키 리매핑",
        chordRemapEnableCaption: "키 조합(keyDown/keyUp, 반복, 앱별 범위)을 가로채어 보조키 누수 없이 다단계 동작을 실행합니다.",
        gestureImportLegacyButton: "~/.gesture/config.json 가져오기",
        gestureResetPresetsButton: "프리셋 초기화",
        gestureAddRuleButton: "제스처 추가",
        chordAddRuleButton: "키 리매핑 추가"
    )

    static let ru = YToolsIntegrationStrings(
        syncSectionTitle: "Облачная синхронизация (Jianguoyun WebDAV · E2EE)",
        syncEnableToggle: "Синхронизировать буфер обмена между устройствами",
        syncCaption: "Сквозное шифрование PBKDF2-SHA256 (600 000 раундов) и AES-256-GCM в формате YTCE2, совместимом с YTools для Windows. Неизменённые заголовки 4 КБ опрашиваются каждые 15 минут без загрузки шифротекста.",
        syncFolderLabel: "Удалённая папка WebDAV",
        syncFolderPlaceholder: "YTools",
        syncPropagateDeletes: "Передавать удаления на другие синхронизированные устройства",
        syncPropagateDeletesCaption: "Записывает зашифрованные маркеры удаления, чтобы очистка или удаление записи убирало её на связанных клиентах Windows и Mac.",
        syncConfigureCredentials: "Настроить учётные данные Jianguoyun…",
        syncUpdateCredentials: "Обновить учётные данные…",
        syncNowButton: "Синхронизировать сейчас",
        syncCredentialsConfigured: "Хранилище Связки ключей готово",
        syncCredentialsMissing: "Требуются учётные данные",
        syncModalTitle: "Jianguoyun WebDAV и ключ E2EE",
        syncAccountLabel: "Email аккаунта Jianguoyun",
        syncAppPasswordLabel: "Пароль приложения WebDAV",
        syncPassphraseLabel: "Парольная фраза E2EE (от 12 символов)",
        syncPassphraseHint: "Должна точно совпадать с фразой в YTools на вашем ПК Windows. Хранится только в локальном хранилище под защитой Связки ключей macOS и не экспортируется в резервные копии.",
        syncSaveButton: "Сохранить в хранилище",
        syncCancelButton: "Отмена",
        extensionsSectionTitle: "Расширения YTools",
        extensionsSectionFooter: "Офлайн-словарь, проверка орфографии, интерактивная навигация по папкам, атомарный перенос без перезаписи, поиск по пиньинь и Крупный шрифт.",
        dictionaryToggle: "Поиск в системном словаре (define / dict)",
        dictionaryAutoToggle: "Автоматически искать одиночные английские слова без префикса",
        spellToggle: "Подсказки английской орфографии (spell)",
        directoryNavToggle: "Интерактивная навигация по папкам (/ и ~) и безопасное копирование/перемещение",
        pinyinFilesToggle: "Поиск по китайскому пиньинь и инициалам в файлах и буфере обмена",
        largeTypeToggle: "Баннер крупным шрифтом (⌘L на любой строке)",
        actionLargeType: "Показать крупным шрифтом",
        actionCopyToFolder: "Безопасно скопировать в папку…",
        actionMoveToFolder: "Безопасно переместить в папку…",
        actionBufferAdd: "Добавить в буфер файлов",
        actionBufferCopyAll: "Скопировать файлы из буфера сюда…",
        actionBufferClear: "Очистить буфер файлов",
        dictionarySubtitlePrefix: "Словарь",
        spellSubtitlePrefix: "Орфография",
        folderBrowserSubtitle: "Обозреватель папок · Return или Tab для открытия",
        gestureCardTitle: "Мультитач-жесты трекпада и автоматизация клавиатуры",
        gestureEnableTitle: "Жесты смахивания и щипка (2–5 пальцев)",
        gestureEnableCaption: "Назначает смахивания 2–5 пальцами и щипки 4–5 пальцами на сочетания клавиш, URL, приложения или скрипты с защитой от касаний ладонью.",
        chordRemapEnableTitle: "Глобальные горячие клавиши и чистое переназначение аккордов",
        chordRemapEnableCaption: "Перехватывает комбинации клавиш (keyDown/keyUp, повтор, область по приложению) и выполняет многошаговые действия без утечки модификаторов.",
        gestureImportLegacyButton: "Импортировать ~/.gesture/config.json",
        gestureResetPresetsButton: "Сбросить пресеты",
        gestureAddRuleButton: "Добавить жест",
        chordAddRuleButton: "Добавить переназначение"
    )

    static let tr = YToolsIntegrationStrings(
        syncSectionTitle: "Bulut Eşitleme (Jianguoyun WebDAV · E2EE)",
        syncEnableToggle: "Panoyu aygıtlar arasında eşitle",
        syncCaption: "Windows için YTools ile uyumlu YTCE2 biçiminde PBKDF2-SHA256 (600.000 tur) ve AES-256-GCM uçtan uca şifreleme kullanır. Değişmeyen 4 KB aygıt başlıkları şifreli veri indirilmeden 15 dakikada bir kontrol edilir.",
        syncFolderLabel: "Uzak WebDAV klasörü",
        syncFolderPlaceholder: "YTools",
        syncPropagateDeletes: "Öğe silme işlemlerini diğer eşitlenen aygıtlara yansıt",
        syncPropagateDeletesCaption: "Bir öğeyi sildiğinizde eşleştirilmiş Windows ve Mac istemcilerinden de kaldırılması için şifreli silme işaretleri yazar.",
        syncConfigureCredentials: "Jianguoyun Kimlik Bilgilerini Ayarla…",
        syncUpdateCredentials: "Kimlik Bilgilerini Güncelle…",
        syncNowButton: "Şimdi Eşitle",
        syncCredentialsConfigured: "Anahtar Zinciri kasası hazır",
        syncCredentialsMissing: "Kimlik bilgileri gerekli",
        syncModalTitle: "Jianguoyun WebDAV ve E2EE Anahtarı",
        syncAccountLabel: "Jianguoyun hesap e-postası",
        syncAppPasswordLabel: "WebDAV uygulama parolası",
        syncPassphraseLabel: "Uçtan uca eşitleme parolası (en az 12 karakter)",
        syncPassphraseHint: "Windows bilgisayarınızdaki YTools parolasıyla birebir aynı olmalıdır. Yalnızca macOS Anahtar Zinciri korumalı yerel kasada saklanır, Ayarlar yedeklerine aktarılmaz.",
        syncSaveButton: "Kasaya Kaydet",
        syncCancelButton: "Vazgeç",
        extensionsSectionTitle: "YTools Uzantıları",
        extensionsSectionFooter: "Çevrimdışı sözlük, yazım önerileri, etkileşimli klasör gezintisi, üzerine yazmayan atomik dosya aktarımı, Pinyin eşleştirme ve Büyük Yazı.",
        dictionaryToggle: "Sistem Sözlüğü araması (define / dict)",
        dictionaryAutoToggle: "Tek İngilizce sözcükleri ön ek olmadan otomatik tanımla",
        spellToggle: "İngilizce yazım önerileri (spell)",
        directoryNavToggle: "Etkileşimli klasör gezintisi (/ ve ~) ve güvenli kopyalama/taşıma",
        pinyinFilesToggle: "Dosya ve pano aramasında Çince Pinyin ve baş harfleri eşleştir",
        largeTypeToggle: "Büyük Yazı bandı (herhangi bir satırda ⌘L)",
        actionLargeType: "Büyük Yazı ile Göster",
        actionCopyToFolder: "Klasöre Güvenli Kopyala…",
        actionMoveToFolder: "Klasöre Güvenli Taşı…",
        actionBufferAdd: "Dosya Tamponuna Ekle",
        actionBufferCopyAll: "Tampondaki Dosyaları Buraya Kopyala…",
        actionBufferClear: "Dosya Tamponunu Temizle",
        dictionarySubtitlePrefix: "Sözlük",
        spellSubtitlePrefix: "Yazım",
        folderBrowserSubtitle: "Klasör Gezgini · Açmak için Return veya Tab",
        gestureCardTitle: "İzleme Dörtgeni Çoklu Dokunma Hareketleri ve Klavye Otomasyonu",
        gestureEnableTitle: "Çok parmaklı kaydırma ve kıstırma hareketleri (2–5 parmak)",
        gestureEnableCaption: "Avuç içi ve yanlış dokunma korumasıyla 2–5 parmak kaydırma ve 4–5 parmak kıstırma/açma hareketlerini kısayollara, URL’lere, uygulamalara veya betiklere atar.",
        chordRemapEnableTitle: "Genel klavye kısayolları ve temiz tuş kombinasyonu yeniden eşleme",
        chordRemapEnableCaption: "Tuş kombinasyonlarını (keyDown/keyUp, yineleme, uygulama kapsamı) yakalar ve değiştirici tuş sızıntısı olmadan çok adımlı eylemler çalıştırır.",
        gestureImportLegacyButton: "~/.gesture/config.json İçe Aktar",
        gestureResetPresetsButton: "Varsayılanları Sıfırla",
        gestureAddRuleButton: "Hareket Ekle",
        chordAddRuleButton: "Tuş Eşleme Ekle"
    )
}
