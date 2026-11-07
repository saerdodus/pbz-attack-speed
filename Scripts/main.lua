--[[
    pbz-attack-speed — 影之刃零（Phantom Blade Zero）独立「攻击速度」UE4SS 模组
    -------------------------------------------------------------------------
    实现思路（攻速饰品的同款机制研究）：
      - 挂钩 6 个近战攻击技能（轻击/重击/空中轻击/
        空中重击/Simple 通用攻击/Simple 空中攻击）的 K2_ActivateAbility；
      - 每次攻击激活后，用 ability:GetPlayTimelineTask() 拿到该次攻击的
        LGATask_PlayTimeline 对象（驱动出招动画和判定窗口的时间轴）；
      - 该对象上有一个没有暴露到 SDK 的 float 属性 PBZTimelinePlayRate（偏移
        0xA8），用 RegisterCustomProperty 动态注册后读取，再调用
        task:SetPlayRate(原速率 × 倍率)，随后回读校验；
      - 攻击速度就是整条出招时间轴的播放倍率，所以整个出招（动作、判定窗口）
        一起变快。

    本模组只做一件事：把玩家每次近战攻击的播放速率乘以 (1 + 配置百分比/100)，
    不需要装备、不写存档、不依赖 pak，只依赖 UE4SS。
]]

local MOD_NAME = "pbz-attack-speed"
local ATTACKS = {
    { "LightAttack",    "/PBZCombatAsset/Prototypes/Abilities/Base/BP_LightAttack_Base.BP_LightAttack_Base_C:K2_ActivateAbility" },
    { "HeavyAttack",    "/PBZCombatAsset/Prototypes/Abilities/Base/BP_HeavyAttack_Base.BP_HeavyAttack_Base_C:K2_ActivateAbility" },
    { "LightAttackAir", "/PBZCombatAsset/Prototypes/Abilities/Base/BP_LightAttack_Air_Base.BP_LightAttack_Air_Base_C:K2_ActivateAbility" },
    { "HeavyAttackAir", "/PBZCombatAsset/Prototypes/Abilities/Base/BP_HeavyAttack_Air_Base.BP_HeavyAttack_Air_Base_C:K2_ActivateAbility" },
    { "SimpleAttack",   "/MagCombatAbilities/Abilities/BP_ActionAbilityBase_Simple.BP_ActionAbilityBase_Simple_C:K2_ActivateAbility" },
    { "SimpleAttackAir","/MagCombatAbilities/Abilities/BP_ActionAbilityBase_Simple_Air.BP_ActionAbilityBase_Simple_Air_C:K2_ActivateAbility" },
}

local DEFAULTS = {
    enabled = true,
    attack_speed_percent = 30,
    apply_to_air_attacks = true,
    property_offset = 0xA8,   -- LGATask_PlayTimeline + 0xA8, float
    log = true,
    debug = false,
}

-- ---------------------------------------------------------------- 路径/日志
local function script_dir()
    local source = (debug.getinfo(1, "S") or {}).source or ""
    source = source:gsub("^@", ""):gsub("/", "\\")
    return source:match("^(.*)\\[^\\]*$") or "."
end
local SCRIPT_DIR = script_dir()
local MOD_DIR = SCRIPT_DIR
if MOD_DIR:sub(-8) == "\\Scripts" then MOD_DIR = MOD_DIR:sub(1, -9) end
local CONFIG_PATH = MOD_DIR .. "\\config.txt"
local LOG_PATH = MOD_DIR .. "\\attack_speed_log.txt"

local log_enabled = true
local log_file = nil
local function log_open()
    if not log_enabled then return end
    if log_file then pcall(function() log_file:close() end) end
    local ok, handle = pcall(io.open, LOG_PATH, "w")
    log_file = ok and handle or nil
end
local function log(msg)
    if not log_enabled then return end
    local okDate, stamp = pcall(os.date, "%H:%M:%S")
    if not okDate or not stamp then stamp = tostring(os.time and os.time() or 0) end
    local line = string.format("[%s] %s", tostring(stamp), tostring(msg))
    print("[" .. MOD_NAME .. "] " .. tostring(msg))
    if log_file then
        pcall(function()
            log_file:write(line .. "\r\n")
            log_file:flush()
        end)
    end
end

-- ---------------------------------------------------------------- 小工具
local function isValid(value)
    if value == nil then return false end
    local ok, result = pcall(function() return value:IsValid() end)
    return ok and result == true
end
local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end
local function unwrap(value)
    if value == nil or type(value) ~= "userdata" then return value end
    local ok, result = pcall(function() return value:Get() end)
    return ok and result or value
end
local function trim(text)
    return (text or ""):match("^%s*(.-)%s*$") or ""
end
local cachedObjects = {}
local function object(path)
    local value = cachedObjects[path]
    if isValid(value) then return value end
    value = StaticFindObject(path)
    if not isValid(value) then error("missing " .. path) end
    cachedObjects[path] = value
    return value
end

-- ---------------------------------------------------------------- 配置
local config = {}
local function parse_value(raw)
    raw = trim(raw)
    if raw == "" then return nil end
    local lower = raw:lower()
    if lower == "true" then return true end
    if lower == "false" then return false end
    local hex = raw:match("^0[xX](%x+)$")
    if hex then return tonumber(hex, 16) end
    local number = tonumber(raw)
    if number then return number end
    return raw
end

local function write_default_config()
    local ok, handle = pcall(io.open, CONFIG_PATH, "w")
    if not ok or not handle then return end
    pcall(function()
        handle:write([[
# ============================================================
#  pbz-attack-speed 配置文件（UTF-8）
#  改完保存后，游戏内按 Ctrl+F9 重新读取，不需要重启游戏
# ============================================================

# 攻击速度提升百分比：
#   30  = 攻击时间轴播放速率 ×1.30（+30%）
#   0   = 不加速
#   100 = ×2.00
# 建议 0 ~ 100；上限 500
attack_speed_percent = 30

# 是否对空中轻击 / 空中重击也生效
apply_to_air_attacks = true

# 总开关（游戏内 Ctrl+F8 也可以切换）
enabled = true

# 写日志到 attack_speed_log.txt（排查问题用）
log = true

# 每次攻击都写一条详细日志（正常游玩建议 false）
debug = false

# 高级：时间轴速率属性在 LGATask_PlayTimeline 上的偏移
# 默认 0xA8（UE 5.7.4 / CL-302256 已验证），游戏大版本更新后才可能需要改
property_offset = 0xA8
]])
        handle:close()
    end)
end

local function load_config()
    local result = {}
    for key, value in pairs(DEFAULTS) do result[key] = value end
    local exists = false
    local ok, handle = pcall(io.open, CONFIG_PATH, "r")
    if ok and handle then
        exists = true
        local content = handle:read("*a") or ""
        handle:close()
        local warnings = {}
        for line in content:gmatch("[^\r\n]+") do
            local body = line
            local hash = body:find("#", 1, true)
            if hash then body = body:sub(1, hash - 1) end
            local semi = body:find(";", 1, true)
            if semi then body = body:sub(1, semi - 1) end
            body = trim(body)
            if body ~= "" then
                local key, value = body:match("^([%w_]+)%s*=%s*(.-)$")
                if key then
                    key = key:lower()
                    if DEFAULTS[key] == nil then
                        warnings[#warnings + 1] = "忽略未知配置项: " .. key
                    else
                        local parsed = parse_value(value)
                        if parsed == nil then
                            warnings[#warnings + 1] = "配置项为空，使用默认值: " .. key
                        else
                            result[key] = parsed
                        end
                    end
                else
                    warnings[#warnings + 1] = "无法解析的行: " .. body
                end
            end
        end
        result._warnings = warnings
    end
    if not exists then
        write_default_config()
        result._created = true
    end
    -- 类型/范围校验
    result.enabled = result.enabled == true
    result.apply_to_air_attacks = result.apply_to_air_attacks == true
    result.log = result.log ~= false
    result.debug = result.debug == true
    if not finite(result.attack_speed_percent) then result.attack_speed_percent = DEFAULTS.attack_speed_percent end
    result.attack_speed_percent = math.max(-90, math.min(500, result.attack_speed_percent))
    if not finite(result.property_offset) or result.property_offset < 0 or result.property_offset > 0x1000 then
        result.property_offset = DEFAULTS.property_offset
    end
    result.property_offset = math.floor(result.property_offset)
    return result
end

local function multiplier()
    if not config.enabled then return 1 end
    return 1 + config.attack_speed_percent / 100
end

-- ---------------------------------------------------------------- 玩家查找
local okHelpers, UEHelpers = pcall(require, "UEHelpers")
if not okHelpers or type(UEHelpers) ~= "table" then
    UEHelpers = nil
end

local cachedPlayer, playerNextAt = nil, 0
local PLAYER_TTL = 2

local function find_player_fallback()
    local list = FindAllOf("PlayerController") or FindAllOf("Controller")
    if list then
        for _, controller in ipairs(list) do
            if isValid(controller) then
                local isLocal = false
                pcall(function()
                    if controller.IsPlayerController then
                        isLocal = controller:IsPlayerController() == true
                    end
                    if not isLocal and controller.IsLocalPlayerController then
                        isLocal = controller:IsLocalPlayerController() == true
                    end
                end)
                if isLocal then
                    local pawn = nil
                    pcall(function() pawn = controller.Pawn end)
                    if isValid(pawn) then return pawn end
                end
            end
        end
    end
    return nil
end

local function player()
    local now = os.time()
    if isValid(cachedPlayer) and now < playerNextAt then return cachedPlayer end
    cachedPlayer = nil
    if UEHelpers and UEHelpers.GetPlayer then
        local ok, value = pcall(UEHelpers.GetPlayer)
        if ok and isValid(value) then cachedPlayer = value end
    end
    if not isValid(cachedPlayer) then
        cachedPlayer = find_player_fallback()
    end
    playerNextAt = now + PLAYER_TTL
    return cachedPlayer
end

-- ---------------------------------------------------------------- 时间轴速率属性
local propertyReady = false
local propertyFailedLogged = false
local propertyRetryAt = 0

local function ensure_property()
    if propertyReady then return true end
    local now = os.time()
    if now < propertyRetryAt then return false end
    propertyRetryAt = now + 2
    local ok, err = pcall(function()
        local system = object("/Script/Engine.Default__KismetSystemLibrary")
        local version = system:GetEngineVersion()
        if version ~= nil and type(version) ~= "string" then
            local convOk, text = pcall(function() return version:ToString() end)
            if convOk then version = text end
        end
        version = tostring(version)
        if not version:find("5.7.4", 1, true) then
            log("警告：当前引擎版本 " .. version .. " 未验证；仍尝试注册，若攻击无效果请看日志")
        end
        RegisterCustomProperty({
            Name = "PBZTimelinePlayRate",
            Type = PropertyTypes.FloatProperty,
            BelongsToClass = "/Script/LegoAbility.LGATask_PlayTimeline",
            OffsetInternal = config.property_offset,
        })
    end)
    if ok then
        propertyReady = true
        log(string.format("攻击时间轴属性已注册 (PBZTimelinePlayRate @ 0x%X)", config.property_offset))
        return true
    end
    if not propertyFailedLogged then
        propertyFailedLogged = true
        log("注册攻击时间轴属性失败（可能还没进存档/游戏版本不符）：" .. tostring(err))
    end
    return false
end

-- ---------------------------------------------------------------- 速率应用
local records = {}   -- task address -> { task, ability, base, applied, lastLog }

local function restore_record(record, reason)
    if not isValid(record.task) then return end
    local ok, current = pcall(function() return record.task.PBZTimelinePlayRate end)
    if ok and finite(current) and math.abs(current - record.applied) < 0.001 then
        pcall(function() record.task:SetPlayRate(record.base) end)
        if config.debug then
            log(string.format("恢复攻击速率 %.4f -> %.4f (%s)", current, record.base, tostring(reason or "")))
        end
    end
end

local function restore_all(reason)
    for address, record in pairs(records) do
        restore_record(record, reason)
        records[address] = nil
    end
end

-- 对一个攻击技能当前的时间轴任务应用倍率。返回 true 表示这个任务已处理。
local function apply_for_ability(ability, why)
    local p = player()
    if not isValid(p) or not isValid(ability) then return false end
    local okAvatar, rawAvatar = pcall(function() return ability:GetAvatarActorFromActorInfo() end)
    if not okAvatar then return false end
    local avatar = unwrap(rawAvatar)
    if not isValid(avatar) or avatar:GetAddress() ~= p:GetAddress() then return false end

    local okTask, rawTask = pcall(function() return ability:GetPlayTimelineTask() end)
    if not okTask then return false end
    local task = unwrap(rawTask)
    if not isValid(task) then return false end

    local okRate, rate = pcall(function() return task.PBZTimelinePlayRate end)
    if not okRate or not finite(rate) or rate <= 0 or rate > 16 then return false end

    local address = task:GetAddress()
    local record = records[address]
    if record == nil then
        record = { task = task, ability = ability, base = rate, applied = rate }
        records[address] = record
    else
        -- 如果游戏自己把速率改了（重置/别的 mod/连段阶段），以当前值为新基准
        if math.abs(rate - record.applied) >= 0.001 then record.base = rate end
        record.ability = ability
    end

    local target = record.base * multiplier()
    if target > 16 then target = 16 end
    if target < 0.001 then target = 0.001 end
    if math.abs(rate - target) < 0.001 then
        record.applied = target
        return true
    end

    local okSet = pcall(function() task:SetPlayRate(target) end)
    if not okSet then
        log("SetPlayRate 调用失败，已放弃该任务（" .. tostring(why) .. "）")
        records[address] = nil
        return false
    end
    local okBack, actual = pcall(function() return task.PBZTimelinePlayRate end)
    if not okBack or not finite(actual) or math.abs(actual - target) > 0.002 then
        log(string.format("速率回读校验失败 target=%.4f actual=%s，已放弃该任务（属性偏移可能不对）",
            target, tostring(actual)))
        records[address] = nil
        return false
    end
    record.applied = target
    if config.debug then
        log(string.format("%s: 攻击速率 %.4f -> %.4f (基础 %.4f, ×%.2f)",
            tostring(why), rate, actual, record.base, multiplier()))
    end
    return true
end

local function is_air_attack(name)
    return name == "LightAttackAir" or name == "HeavyAttackAir" or name == "SimpleAttackAir"
end

local function handle_attack(ability, name)
    if not config.enabled then return end
    if is_air_attack(name) and not config.apply_to_air_attacks then return end
    if not ensure_property() then return end
    apply_for_ability(ability, name)
    -- 时间轴任务通常在技能激活后 1~2 帧才创建，按几个时间点重试
    for _, delay in ipairs({ 8, 30, 90, 200 }) do
        ExecuteInGameThreadWithDelay(delay, function()
            pcall(apply_for_ability, ability, name .. "+" .. tostring(delay) .. "ms")
            return false
        end)
    end
end

-- ---------------------------------------------------------------- 攻击挂钩
local hooks = {}
local function hook_required(name)
    return config.apply_to_air_attacks or not is_air_attack(name)
end
local function all_hooks_ready()
    for _, entry in ipairs(ATTACKS) do
        if hook_required(entry[1]) and not hooks[entry[1]] then return false end
    end
    return true
end

local function install_hooks()
    for _, entry in ipairs(ATTACKS) do
        local name, path = entry[1], entry[2]
        if hook_required(name) and not hooks[name] then
            local ok, pre = pcall(function()
                if not isValid(StaticFindObject(path)) then return nil end
                return RegisterHook(path, function(selfParam)
                    local okAbility, ability = pcall(unwrap, selfParam)
                    if not okAbility or not isValid(ability) then return end
                    ExecuteInGameThreadWithDelay(1, function()
                        pcall(handle_attack, ability, name)
                        return false
                    end)
                end)
            end)
            if ok and pre ~= nil then
                hooks[name] = true
                log("已挂钩攻击技能: " .. name)
            end
        end
    end
end

-- ---------------------------------------------------------------- 清理循环
local lastPlayerAddress = nil
local lastAlive = nil
local nextCleanupAt = 0

local function player_alive(p)
    local ok, asc = pcall(function()
        return object("/Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary"):GetAbilitySystemComponent(p)
    end)
    if not ok or not isValid(asc) then return nil end
    local okSet, attributes = pcall(function()
        return asc:GetAttributeSet(object("/Script/CharacterBasics.BasicAttributeSet"))
    end)
    if not okSet or not isValid(attributes) then return nil end
    local okHealth, health = pcall(function() return attributes.Health.CurrentValue end)
    if okHealth and finite(health) then return health > 0 end
    return nil
end

local function cleanup()
    local p = player()
    if not isValid(p) then
        if next(records) ~= nil then restore_all("no-player") end
        lastPlayerAddress = nil
        lastAlive = nil
        return
    end
    -- 没有正在跟踪的攻击任务时不需要每 250ms 查一次属性
    if next(records) == nil then
        lastPlayerAddress = p:GetAddress()
        return
    end
    local address = p:GetAddress()
    if lastPlayerAddress ~= nil and address ~= lastPlayerAddress then
        restore_all("pawn-changed")
    end
    lastPlayerAddress = address

    local alive = player_alive(p)
    if alive == false and lastAlive ~= false then
        restore_all("player-dead")
    end
    lastAlive = alive

    for taskAddress, record in pairs(records) do
        local taskOk = isValid(record.task)
        local active = false
        if isValid(record.ability) then
            local okActive, value = pcall(function() return record.ability.bIsActive end)
            if okActive and value == true then active = true end
        end
        if not taskOk then
            records[taskAddress] = nil
        elseif not active then
            restore_record(record, "ability-finished")
            records[taskAddress] = nil
        end
    end
end

-- ---------------------------------------------------------------- 热键/热重载
local function apply_hook_state()
    -- 配置里 apply_to_air_attacks 变化后，需要补挂/忽略空中攻击
    pcall(install_hooks)
end

local function reload_config(reason)
    local newConfig = load_config()
    local oldPercent = config.attack_speed_percent
    local oldEnabled = config.enabled
    local oldAir = config.apply_to_air_attacks
    -- 保留旧的日志开关语义：重新读取后才能真正应用
    local oldLog = config.log
    config = newConfig
    log_enabled = config.log ~= false
    if not log_enabled then
        -- 关闭日志时也把之前的日志文件句柄关掉
        if log_file then pcall(function() log_file:close() end) end
        log_file = nil
    elseif log_file == nil then
        log_open()
    end
    restore_all("config-reload")
    if not config.enabled then
        log(string.format("配置已重新加载：已关闭加速 (原 +%.0f%%)", oldPercent))
    else
        log(string.format("配置已重新加载：+%.0f%% 攻击速度（播放速率 ×%.2f）%s",
            config.attack_speed_percent, multiplier(),
            (oldPercent ~= config.attack_speed_percent) and "，下一刀生效" or ""))
    end
    if oldEnabled ~= config.enabled or oldAir ~= config.apply_to_air_attacks then
        pcall(apply_hook_state)
    end
    if type(reason) == "string" and reason ~= "" then log("（触发方式：" .. reason .. "）") end
    if type(config._warnings) == "table" then
        for _, warning in ipairs(config._warnings) do log("配置提醒: " .. warning) end
    end
end

local function toggle_enabled()
    config.enabled = not config.enabled
    restore_all("toggle")
    if config.enabled then
        log(string.format("已开启攻击加速：+%.0f%%（下一刀生效）", config.attack_speed_percent))
    else
        log("已关闭攻击加速，当前攻击速率已恢复")
    end
end

local function register_hotkeys()
    pcall(function()
        RegisterKeyBind(Key.F9, { ModifierKey.CONTROL }, function()
            ExecuteInGameThread(function() reload_config("Ctrl+F9") end)
        end)
        RegisterKeyBind(Key.F8, { ModifierKey.CONTROL }, function()
            ExecuteInGameThread(function() toggle_enabled() end)
        end)
    end)
end

-- ---------------------------------------------------------------- 启动
do
    -- 先读配置，再决定日志开关（日志路径固定，先清空旧日志）
    local initial = load_config()
    log_enabled = initial.log ~= false
    log_open()
    config = initial
    log(string.format("%s 已加载：+%.0f%% 攻击速度（播放速率 ×%.2f），空中攻击=%s",
        MOD_NAME, config.attack_speed_percent, multiplier(),
        config.apply_to_air_attacks and "开启" or "关闭"))
    if config._created then
        log("首次运行：已生成默认配置文件 " .. CONFIG_PATH .. "，可自行修改数值")
    end
    if type(config._warnings) == "table" then
        for _, warning in ipairs(config._warnings) do log("配置提醒: " .. warning) end
    end
    register_hotkeys()

    -- 每 1 秒检查一次是不是进入了存档/攻击类是否加载完成；全部挂上后停止重试
    LoopInGameThreadWithDelay(1000, function()
        if isValid(player()) then
            local ok, err = pcall(install_hooks)
            if not ok then log("挂钩重试失败：" .. tostring(err)) end
        end
        return not all_hooks_ready()
    end)

    -- 250ms 清理一次结束的攻击任务，避免残留速率
    LoopInGameThreadWithDelay(250, function()
        local ok, err = pcall(cleanup)
        if not ok and config.debug then log("清理循环错误：" .. tostring(err)) end
        return true
    end)
end
