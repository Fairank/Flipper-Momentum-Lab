import Foundation

/// Phone display aliases only. RPC report keys and values remain unchanged in storage.
public enum DeviceInfoLabel {
    private static let titles: [String: String] = [
        "device_info_major": "设备信息主版本", "device_info_minor": "设备信息次版本",
        "hardware_model": "设备型号", "hardware_uid": "设备标识",
        "hardware_otp_ver": "出厂配置版本", "hardware_timestamp": "出厂时间",
        "hardware_ver": "硬件版本", "hardware_target": "硬件目标",
        "hardware_body": "机身版本", "hardware_connect": "接口版本",
        "hardware_display": "显示屏版本", "hardware_color": "机身颜色",
        "hardware_region": "硬件区域", "hardware_region_provisioned": "已配置区域",
        "hardware_name": "设备名称",
        "firmware_commit": "固件提交", "firmware_commit_dirty": "固件有本地修改",
        "firmware_branch": "固件分支", "firmware_branch_num": "分支编号",
        "firmware_version": "固件版本", "firmware_build_date": "构建日期",
        "firmware_target": "固件目标", "firmware_api_major": "应用接口主版本",
        "firmware_api_minor": "应用接口次版本", "firmware_origin_fork": "固件项目",
        "firmware_origin_git": "源码地址",
        "radio_alive": "无线模块状态", "radio_mode": "无线运行模式",
        "radio_fus_major": "无线升级服务主版本", "radio_fus_minor": "无线升级服务次版本",
        "radio_fus_sub": "无线升级服务修订版本", "radio_fus_sram2b": "无线升级服务 SRAM2B",
        "radio_fus_sram2a": "无线升级服务 SRAM2A", "radio_fus_flash": "无线升级服务闪存",
        "radio_stack_type": "蓝牙协议栈类型", "radio_stack_major": "蓝牙协议栈主版本",
        "radio_stack_minor": "蓝牙协议栈次版本", "radio_stack_sub": "蓝牙协议栈修订版本",
        "radio_stack_branch": "蓝牙协议栈分支", "radio_stack_release": "蓝牙协议栈发行类型",
        "radio_stack_sram2b": "蓝牙协议栈 SRAM2B", "radio_stack_sram2a": "蓝牙协议栈 SRAM2A",
        "radio_stack_sram1": "蓝牙协议栈 SRAM1", "radio_stack_flash": "蓝牙协议栈闪存",
        "radio_ble_mac": "蓝牙 MAC 地址",
        "enclave_valid_keys": "安全存储有效密钥数", "enclave_valid": "安全存储校验通过",
    ]

    public static func title(for key: String) -> String { titles[key] ?? key }

    /// Only known presentation enums are translated; names, hashes and unknown values are data.
    public static func value(for value: String, key: String) -> String {
        switch (key, value) {
        case ("firmware_commit_dirty", "true"), ("enclave_valid", "true"): return "是"
        case ("firmware_commit_dirty", "false"), ("enclave_valid", "false"): return "否"
        case ("radio_alive", "true"): return "可用"
        case ("radio_alive", "false"): return "不可用"
        case ("radio_mode", "Stack"): return "蓝牙协议栈"
        case ("radio_mode", "FUS"): return "固件升级服务（FUS）"
        default: return value
        }
    }
}

/// Produces Chinese display text without replacing the original error passed through a session.
public enum PhoneErrorDescription {
    public static func describe(_ error: Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription,
           containsHan(description) {
            return description
        }
        let original = error as NSError
        switch original.domain {
        case "CBErrorDomain":
            return "蓝牙通信失败，请检查连接后重试。（错误 \(original.code)）"
        case "CBATTErrorDomain":
            return "设备蓝牙请求失败，请检查连接后重试。（错误 \(original.code)）"
        case NSURLErrorDomain:
            return "网络请求失败，请检查网络后重试。（错误 \(original.code)）"
        default:
            return "操作未完成（\(original.domain) / \(original.code)）。"
        }
    }

    private static func containsHan(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF,
                 0x20000...0x2FA1F, 0x30000...0x323AF:
                return true
            default: return false
            }
        }
    }
}
