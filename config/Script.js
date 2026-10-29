function main(config, profileName) {
  function createNameMap() {
    return Object.create(null);
  }

  function hasOwn(object, key) {
    return Object.prototype.hasOwnProperty.call(object, key);
  }

  var groupNames = createNameMap();
  var groupNameByLower = createNameMap();
  var proxyNames = createNameMap();
  var proxyNameByLower = createNameMap();
  var managedGroupNameByPreferred = createNameMap();

  function normalizeName(name) {
    return String(name || "").toLowerCase();
  }

  function rememberGroupName(name) {
    if (!name) {
      return;
    }
    groupNames[name] = true;
    var lower = normalizeName(name);
    if (!groupNameByLower[lower]) {
      groupNameByLower[lower] = name;
    }
  }

  var ruleProviders = config["rule-providers"];

  var rawGroups = Array.isArray(config["proxy-groups"]) ? config["proxy-groups"] : [];
  var groups = [];
  for (var i = 0; i < rawGroups.length; i++) {
    if (rawGroups[i] && rawGroups[i].name) {
      groups.push(rawGroups[i]);
      rememberGroupName(rawGroups[i].name);
    }
  }

  var proxyListKey = "proxies";
  var rawProxies = config.proxies;
  if (!Array.isArray(rawProxies)) {
    for (var configKey in config) {
      if (hasOwn(config, configKey) &&
          configKey !== "proxies" &&
          normalizeName(configKey) === "proxies" &&
          Array.isArray(config[configKey])) {
        proxyListKey = configKey;
        rawProxies = config[configKey];
        break;
      }
    }
  }
  if (!Array.isArray(rawProxies)) {
    rawProxies = [];
  }
  var proxies = [];
  for (var p = 0; p < rawProxies.length; p++) {
    if (rawProxies[p] && rawProxies[p].name) {
      proxies.push(rawProxies[p]);
      proxyNames[rawProxies[p].name] = true;
      proxyNameByLower[normalizeName(rawProxies[p].name)] = rawProxies[p].name;
    }
  }
  config.proxies = proxies;
  if (proxyListKey !== "proxies") {
    delete config[proxyListKey];
  }

  function unique(items) {
    var seen = createNameMap();
    var result = [];
    for (var i = 0; i < items.length; i++) {
      var item = items[i];
      if (item && !seen[item]) {
        seen[item] = true;
        result.push(item);
      }
    }
    return result;
  }

  function findExistingGroup(name) {
    if (groupNames[name]) {
      return name;
    }
    return groupNameByLower[normalizeName(name)] || null;
  }

  function optionExists(name) {
    return name === "DIRECT" || name === "REJECT" || groupNames[name] || proxyNames[name];
  }

  function filterExisting(items) {
    var result = [];
    for (var i = 0; i < items.length; i++) {
      if (optionExists(items[i])) {
        result.push(items[i]);
      }
    }
    return unique(result);
  }

  function findGroup(name) {
    var existingName = findExistingGroup(name);
    if (!existingName) {
      return null;
    }
    for (var i = 0; i < groups.length; i++) {
      if (groups[i] && groups[i].name === existingName) {
        return groups[i];
      }
    }
    return null;
  }

  function findGroupByExactName(name) {
    for (var i = 0; i < groups.length; i++) {
      if (groups[i] && groups[i].name === name) {
        return groups[i];
      }
    }
    return null;
  }

  function proxyNameExists(name) {
    return !!proxyNameByLower[normalizeName(name)];
  }

  function allocateGroupName(preferredName) {
    if (!proxyNameExists(preferredName) && !findExistingGroup(preferredName)) {
      return preferredName;
    }

    var baseName = preferredName + " Group";
    var candidate = baseName;
    var suffix = 2;
    while (proxyNameExists(candidate) || findExistingGroup(candidate)) {
      candidate = baseName + " " + suffix;
      suffix += 1;
    }
    return candidate;
  }

  function findManagedGroup(preferredName) {
    var allocatedName = managedGroupNameByPreferred[preferredName];
    if (allocatedName) {
      return findGroupByExactName(allocatedName);
    }

    var existingGroup = findGroup(preferredName);
    if (existingGroup && !proxyNameExists(existingGroup.name)) {
      managedGroupNameByPreferred[preferredName] = existingGroup.name;
      return existingGroup;
    }

    var baseName = preferredName + " Group";
    for (var suffix = 1; suffix < 100; suffix++) {
      var candidate = suffix === 1 ? baseName : baseName + " " + suffix;
      var fallbackGroup = findGroup(candidate);
      if (fallbackGroup && !proxyNameExists(fallbackGroup.name)) {
        managedGroupNameByPreferred[preferredName] = fallbackGroup.name;
        return fallbackGroup;
      }
      if (!fallbackGroup && !proxyNameExists(candidate)) {
        break;
      }
    }

    return null;
  }

  function ensureGroup(name, options) {
    var finalName = allocateGroupName(name);
    var finalOptions = filterExisting(options);
    if (finalOptions.length === 0) {
      finalOptions = ["DIRECT"];
    }
    groups.push({
      name: finalName,
      type: "select",
      proxies: finalOptions
    });
    rememberGroupName(finalName);
    managedGroupNameByPreferred[name] = finalName;
    return finalName;
  }

  function ensureManagedGroup(name, options, fallbackOptions) {
    var existingGroup = findManagedGroup(name);
    var finalOptions = filterExisting(options);
    if (existingGroup) {
      var withoutSelf = [];
      for (var optionIndex = 0; optionIndex < finalOptions.length; optionIndex++) {
        if (finalOptions[optionIndex] !== existingGroup.name) {
          withoutSelf.push(finalOptions[optionIndex]);
        }
      }
      finalOptions = withoutSelf;
    }
    if (finalOptions.length === 0) {
      finalOptions = filterExisting(fallbackOptions || ["DIRECT"]);
    }
    if (finalOptions.length === 0) {
      finalOptions = ["DIRECT"];
    }
    if (existingGroup) {
      var dynamicOptionKeys = [
        "use",
        "filter",
        "exclude-filter",
        "exclude-type",
        "include-all",
        "include-all-proxies",
        "include-all-providers",
        "url",
        "interval",
        "timeout",
        "tolerance",
        "lazy",
        "expected-status",
        "max-failed-times"
      ];
      for (var dynamicKeyIndex = 0; dynamicKeyIndex < dynamicOptionKeys.length; dynamicKeyIndex++) {
        delete existingGroup[dynamicOptionKeys[dynamicKeyIndex]];
      }
      existingGroup.type = "select";
      existingGroup.proxies = finalOptions;
      return existingGroup.name;
    }
    return ensureGroup(name, finalOptions);
  }

  function optionMatches(name, patterns) {
    for (var i = 0; i < patterns.length; i++) {
      if (patterns[i].test(name)) {
        return true;
      }
    }
    return false;
  }

  var originalGroups = [];
  for (var g = 0; g < groups.length; g++) {
    originalGroups.push(groups[g].name);
  }

  // 机场常把「剩余流量 / 套餐到期 / 官网」这类提示做成节点塞进列表，而且名字随订阅更新变化。
  // 选到它们会静默出问题：看着像在用某个落地，实际出口 IP 会漂到别处，
  // 表现是 X 掉登录、Discord 反复跳认证、AI 服务被风控。
  // 所以在收集阶段就排除，不让它们进任何策略组。
  var infoNodePatterns = [
    /导航/, /剩余/, /流量/, /套餐/, /到期/, /过期/, /重置/, /续费/, /试用/,
    /官网/, /订阅/, /购买/, /客服/, /机场/, /群组/, /频道/, /回国/, /回程/, /国内专线/,
    /(^|[^A-Za-z])traffic([^A-Za-z]|$)/i,
    /(^|[^A-Za-z])expire/i,
    /(^|[^A-Za-z])website([^A-Za-z]|$)/i
  ];

  var originalProxies = [];
  var skippedInfoNodes = [];
  for (var pr = 0; pr < proxies.length; pr++) {
    var candidateName = proxies[pr].name;
    if (optionMatches(candidateName, infoNodePatterns)) {
      skippedInfoNodes.push(candidateName);
      continue;
    }
    originalProxies.push(candidateName);
  }
  if (skippedInfoNodes.length > 0) {
    // 必须真的从配置里删掉，不能只是"不建组" —— 那样它们仍会出现在客户端的节点列表里，
    // 用户照样能选到，问题一点没解决。（这个坑踩过：日志说跳过了，实际一个没少。）
    config.proxies = proxies.filter(function (proxy) {
      return !optionMatches(proxy.name, infoNodePatterns);
    });
    console.log("[clash-verge-share-kit] 已剔除 " + skippedInfoNodes.length +
      " 个提示类节点（不是真实落地，选中会导致出口漂移）: " + skippedInfoNodes.join(" / "));
  }
  var proxyProviders = config["proxy-providers"];
  var hasProxyProviders = false;
  if (proxyProviders && typeof proxyProviders === "object") {
    for (var providerName in proxyProviders) {
      if (hasOwn(proxyProviders, providerName)) {
        hasProxyProviders = true;
        break;
      }
    }
  }
  var managedPreferredGroupNames = {
    proxies: true,
    claude: true,
    ai: true,
    google: true,
    youtube: true,
    telegram: true,
    "google + youtube + telegram": true,
    exchange: true,
    hk: true,
    jp: true,
    sg: true,
    tw: true,
    us: true
  };
  var originalCustomGroupNames = createNameMap();
  for (var originalGroupIndex = 0; originalGroupIndex < originalGroups.length; originalGroupIndex++) {
    var originalGroupName = originalGroups[originalGroupIndex];
    if (!hasOwn(managedPreferredGroupNames, normalizeName(originalGroupName))) {
      originalCustomGroupNames[originalGroupName] = true;
    }
  }

  function lookupName(map, name) {
    if (hasOwn(map, name)) {
      return map[name];
    }
    var lowerName = normalizeName(name);
    for (var key in map) {
      if (hasOwn(map, key) && normalizeName(key) === lowerName) {
        return map[key];
      }
    }
    return undefined;
  }

  function ruleReferencesCustomGroup(rule) {
    if (typeof rule !== "string") {
      return false;
    }
    var parts = splitRuleParts(rule);
    if (parts.length < 2) {
      return false;
    }
    var ruleType = String(parts[0] || "").toUpperCase();
    if (ruleType === "SUB-RULE") {
      return false;
    }
    var targetIndex = ruleType === "MATCH" || ruleType === "FINAL" ? 1 : 2;
    return parts.length > targetIndex && lookupName(originalCustomGroupNames, parts[targetIndex]) !== undefined;
  }

  function ruleListReferencesCustomGroup(ruleList) {
    if (!Array.isArray(ruleList)) {
      return false;
    }
    for (var ruleIndex = 0; ruleIndex < ruleList.length; ruleIndex++) {
      if (ruleReferencesCustomGroup(ruleList[ruleIndex])) {
        return true;
      }
    }
    return false;
  }

  var customGroupIsReferenced = ruleListReferencesCustomGroup(config.rules);
  var subRules = config["sub-rules"];
  if (!customGroupIsReferenced && subRules && typeof subRules === "object") {
    for (var subRuleName in subRules) {
      if (hasOwn(subRules, subRuleName) && ruleListReferencesCustomGroup(subRules[subRuleName])) {
        customGroupIsReferenced = true;
        break;
      }
    }
  }
  if (!customGroupIsReferenced && ruleProviders && typeof ruleProviders === "object") {
    for (var compactProviderName in ruleProviders) {
      if (!hasOwn(ruleProviders, compactProviderName)) {
        continue;
      }
      var compactProvider = ruleProviders[compactProviderName];
      // 与规则目标的引用检测（ruleReferencesCustomGroup）同一套大小写不敏感语义
      if (compactProvider && lookupName(originalCustomGroupNames, compactProvider.proxy) !== undefined) {
        customGroupIsReferenced = true;
        break;
      }
    }
  }

  function referencesCustomGroup(name) {
    return typeof name === "string" && hasOwn(originalCustomGroupNames, name);
  }

  if (!customGroupIsReferenced) {
    for (var dialerProxyIndex = 0; dialerProxyIndex < proxies.length; dialerProxyIndex++) {
      if (referencesCustomGroup(proxies[dialerProxyIndex]["dialer-proxy"])) {
        customGroupIsReferenced = true;
        break;
      }
    }
  }
  if (!customGroupIsReferenced && Array.isArray(config.listeners)) {
    for (var listenerIndex = 0; listenerIndex < config.listeners.length; listenerIndex++) {
      if (config.listeners[listenerIndex] &&
          referencesCustomGroup(config.listeners[listenerIndex].proxy)) {
        customGroupIsReferenced = true;
        break;
      }
    }
  }
  if (!customGroupIsReferenced && Array.isArray(config.tunnels)) {
    for (var tunnelIndex = 0; tunnelIndex < config.tunnels.length; tunnelIndex++) {
      if (config.tunnels[tunnelIndex] &&
          referencesCustomGroup(config.tunnels[tunnelIndex].proxy)) {
        customGroupIsReferenced = true;
        break;
      }
    }
  }
  if (!customGroupIsReferenced && config.ntp && typeof config.ntp === "object") {
    if (referencesCustomGroup(config.ntp.proxy)) {
      customGroupIsReferenced = true;
    }
  }

  var compactGroupsEnabled = originalProxies.length > 0 &&
    !hasProxyProviders &&
    !customGroupIsReferenced;

  var preferredGeneralGroups = [
    "节点选择",
    "代理",
    "代理选择",
    "手动切换",
    "自动选择",
    "故障转移",
    "Proxy",
    "Proxy Select",
    "GLOBAL",
    "Global",
    "Auto",
    "Fallback"
  ];

  var generalOptions = [];
  if (!compactGroupsEnabled) {
    for (var pg = 0; pg < preferredGeneralGroups.length; pg++) {
      if (groupNames[preferredGeneralGroups[pg]]) {
        generalOptions.push(preferredGeneralGroups[pg]);
      }
    }
    generalOptions = generalOptions.concat(originalGroups);
  }
  generalOptions = generalOptions.concat(originalProxies).concat(["DIRECT"]);

  var existingProxiesGroup = !compactGroupsEnabled ? findManagedGroup("Proxies") : null;
  var PROXIES_GROUP;
  if (existingProxiesGroup) {
    PROXIES_GROUP = existingProxiesGroup.name;
  } else {
    PROXIES_GROUP = ensureManagedGroup("Proxies", generalOptions, ["DIRECT"]);
  }

  // 地区识别。除了国名缩写，还要覆盖三类容易被漏掉的写法：
  //   1. 只有城市名、不带国名也不带旗帜的节点，如「Los Angeles 01」「大阪 02」
  //   2. 机场自己造的缩写，如「沪美」「深港」「沪日」
  //   3. 直接用 IATA 三字码命名的节点，如「HKG-01」「LAX-02」「NRT-03」
  // 参考同类规则项目（LingJingMaster/Shadowrocket-Rules、IvanSolis1989/Smart-Config-Kit）。
  // 刻意**不写单字**（如「美」「港」）—— 会误匹配到无关的词。
  // 三字码用字母边界匹配：SINGAPORE 里的子串不会被当成 SIN。
  function iataCode(code) {
    return new RegExp("(^|[^A-Za-z])" + code + "([^A-Za-z]|$)", "i");
  }

  var regionPatterns = {
    HK: [/香港/i, /Hong Kong/i, /(^|[^A-Za-z])HK([^A-Za-z]|$)/i, /🇭🇰/, /深港/, /沪港/, /京港/, /广港/,
         iataCode("HKG")],
    JP: [/日本/i, /Japan/i, /Tokyo/i, /Osaka/i, /(^|[^A-Za-z])JP([^A-Za-z]|$)/i, /🇯🇵/, /东京/i, /大阪/i, /沪日/,
         iataCode("NRT"), iataCode("HND"), iataCode("KIX")],
    SG: [/新加坡/i, /Singapore/i, /(^|[^A-Za-z])SG([^A-Za-z]|$)/i, /🇸🇬/, /狮城/, iataCode("SIN")],
    TW: [/台湾/i, /台灣/i, /臺灣/i, /Taiwan/i, /(^|[^A-Za-z])TW([^A-Za-z]|$)/i, /🇹🇼/,
         /Taipei/i, /台北/i, /新北/i, /台中/i, iataCode("TPE")],
    US: [/美国/i, /美國/i, /United States/i, /(^|[^A-Za-z])US([^A-Za-z]|$)/i, /(^|[^A-Za-z])USA([^A-Za-z]|$)/i, /🇺🇸/,
         /Los Angeles/i, /San Jose/i, /Seattle/i, /Chicago/i, /New York/i, /Dallas/i, /Phoenix/i, /Silicon Valley/i,
         /洛杉矶/i, /圣何塞/i, /西雅图/i, /芝加哥/i, /纽约/i, /达拉斯/i, /凤凰城/i, /硅谷/i, /沪美/,
         iataCode("LAX"), iataCode("SFO"), iataCode("SJC"), iataCode("SEA"), iataCode("JFK"), iataCode("ORD")],
    UK: [/英国/i, /英國/i, /United Kingdom/i, /Britain/i, /England/i, /London/i, /(^|[^A-Za-z])UK([^A-Za-z]|$)/i, /🇬🇧/, /伦敦/i,
         iataCode("LHR")]
  };

  var managedGroups = {
    Proxies: PROXIES_GROUP
  };
  var detectedRegions = createNameMap();

  var regionOrder = ["HK", "JP", "SG", "TW", "US", "UK"];
  for (var ro = 0; ro < regionOrder.length; ro++) {
    var region = regionOrder[ro];
    var regionOptions = [];
    var patterns = regionPatterns[region];

    if (!compactGroupsEnabled) {
      for (var og = 0; og < originalGroups.length; og++) {
        if (optionMatches(originalGroups[og], patterns)) {
          regionOptions.push(originalGroups[og]);
        }
      }
    }
    for (var op = 0; op < originalProxies.length; op++) {
      if (optionMatches(originalProxies[op], patterns)) {
        regionOptions.push(originalProxies[op]);
      }
    }

    if (regionOptions.length > 0) {
      detectedRegions[region] = true;
      var existingRegionGroup = !compactGroupsEnabled ? findManagedGroup(region) : null;
      if (existingRegionGroup && regionOptions.indexOf(existingRegionGroup.name) !== -1) {
        managedGroups[region] = existingRegionGroup.name;
      } else {
        managedGroups[region] = ensureManagedGroup(region, regionOptions, ["DIRECT"]);
      }
    }
  }

  if (!managedGroups.US) {
    managedGroups.US = ensureManagedGroup("US", [PROXIES_GROUP, "DIRECT"], ["DIRECT"]);
  }
  // 业务组统一采用「地区优先」：第一个选项是明确的地区组，Proxies（兜底组）降到最后。
  // Claude 与 Codex / OpenAI 统一使用一个 AI 组，出口固定为 US。这样用户只需维护一个
  // 国际 AI 出口，避免两个组被误选成不同地区，导致同一账号的会话出口拆分。
  managedGroups.AI = ensureManagedGroup("AI", [
    detectedRegions.US ? managedGroups.US : null
  ], ["REJECT"]);

  // 兼容旧订阅里已有的 Claude 组：保留为隐藏别名并指向新的 AI 组，避免旧规则、
  // provider、listener、tunnel 或 ntp 引用悬空；新配置不再生成第二个可见业务组。
  var legacyClaudeGroup = findGroup("Claude");
  if (legacyClaudeGroup && legacyClaudeGroup.name !== managedGroups.AI) {
    var legacyClaudeDynamicKeys = [
      "use",
      "filter",
      "exclude-filter",
      "exclude-type",
      "include-all",
      "include-all-proxies",
      "include-all-providers",
      "url",
      "interval",
      "timeout",
      "tolerance",
      "lazy",
      "expected-status",
      "max-failed-times"
    ];
    for (var legacyClaudeKeyIndex = 0; legacyClaudeKeyIndex < legacyClaudeDynamicKeys.length; legacyClaudeKeyIndex++) {
      delete legacyClaudeGroup[legacyClaudeDynamicKeys[legacyClaudeKeyIndex]];
    }
    legacyClaudeGroup.type = "select";
    legacyClaudeGroup.proxies = [managedGroups.AI];
    legacyClaudeGroup.hidden = true;
  }
  // 规则目标仍可使用 Claude 这个历史名称，但实际统一映射到 AI。
  managedGroups.Claude = managedGroups.AI;

  // Google 账号、YouTube 和 Telegram 共用同一个默认 TW 的日常海外出口，
  // 避免同一 Google 账号在 Google 与 YouTube 之间选出不同地区。
  var unifiedGoogleMediaGroup = "Google + YouTube + Telegram";
  managedGroups.GoogleYouTubeTelegram = ensureManagedGroup(unifiedGoogleMediaGroup, [
    managedGroups.TW,
    managedGroups.HK,
    managedGroups.JP,
    managedGroups.SG,
    managedGroups.US,
    PROXIES_GROUP,
    "DIRECT"
  ], ["DIRECT"]);

  function hideManagedAlias(aliasName, targetName) {
    var aliasGroup = findGroup(aliasName);
    if (!aliasGroup || aliasGroup.name === targetName) {
      return;
    }
    var legacyAliasDynamicKeys = [
      "use",
      "filter",
      "exclude-filter",
      "exclude-type",
      "include-all",
      "include-all-proxies",
      "include-all-providers",
      "url",
      "interval",
      "timeout",
      "tolerance",
      "lazy",
      "expected-status",
      "max-failed-times"
    ];
    for (var legacyAliasKeyIndex = 0; legacyAliasKeyIndex < legacyAliasDynamicKeys.length; legacyAliasKeyIndex++) {
      delete aliasGroup[legacyAliasDynamicKeys[legacyAliasKeyIndex]];
    }
    aliasGroup.type = "select";
    aliasGroup.proxies = [targetName];
    aliasGroup.hidden = true;
  }

  // 旧订阅里的三个业务组保留为隐藏别名，避免旧规则、provider、listener、
  // tunnel 或 ntp 引用悬空；新配置只显示统一业务组。
  hideManagedAlias("Google", managedGroups.GoogleYouTubeTelegram);
  hideManagedAlias("YouTube", managedGroups.GoogleYouTubeTelegram);
  hideManagedAlias("Telegram", managedGroups.GoogleYouTubeTelegram);
  managedGroups.Google = managedGroups.GoogleYouTubeTelegram;
  managedGroups.YouTube = managedGroups.GoogleYouTubeTelegram;
  managedGroups.Telegram = managedGroups.GoogleYouTubeTelegram;
  managedGroups.Exchange = ensureManagedGroup("Exchange", [managedGroups.TW, managedGroups.SG], ["REJECT"]);

  // Proxies 可能是在统一业务组建立前由原始组名生成的；旧别名再指向统一组、
  // 统一组又指向 Proxies 时会形成 mihomo 环。移除会回到 Proxies 的受管组边，
  // 保留别名自身指向统一组的兼容语义。
  var generatedProxiesGroup = findGroup(PROXIES_GROUP);
  if (generatedProxiesGroup && Array.isArray(generatedProxiesGroup.proxies)) {
    var proxyGroupCycleNames = createNameMap();
    proxyGroupCycleNames[normalizeName(managedGroups.GoogleYouTubeTelegram)] = true;
    var proxyGroupCycleAliases = ["Claude", "Google", "YouTube", "Telegram"];
    for (var cycleAliasIndex = 0; cycleAliasIndex < proxyGroupCycleAliases.length; cycleAliasIndex++) {
      var cycleAliasGroup = findGroup(proxyGroupCycleAliases[cycleAliasIndex]);
      if (cycleAliasGroup) {
        proxyGroupCycleNames[normalizeName(cycleAliasGroup.name)] = true;
      }
    }
    var safeProxyOptions = [];
    for (var proxyOptionIndex = 0; proxyOptionIndex < generatedProxiesGroup.proxies.length; proxyOptionIndex++) {
      var proxyOption = generatedProxiesGroup.proxies[proxyOptionIndex];
      if (!proxyGroupCycleNames[normalizeName(proxyOption)]) {
        safeProxyOptions.push(proxyOption);
      }
    }
    generatedProxiesGroup.proxies = safeProxyOptions.length > 0 ? unique(safeProxyOptions) : ["DIRECT"];
  }

  var managedTargetMap = createNameMap();
  for (var managedName in managedGroups) {
    if (hasOwn(managedGroups, managedName)) {
      managedTargetMap[managedName] = managedGroups[managedName];
    }
  }

  if (ruleProviders && typeof ruleProviders === "object") {
    for (var ruleProviderName in ruleProviders) {
      if (!hasOwn(ruleProviders, ruleProviderName)) {
        continue;
      }
      var ruleProvider = ruleProviders[ruleProviderName];
      // 与规则目标改写同一套 lookupName 大小写不敏感语义，
      // 避免订阅写法如 proxy: PROXIES 在组名沿用订阅原大小写时悬空
      if (ruleProvider) {
        var mappedProviderProxy = lookupName(managedTargetMap, ruleProvider.proxy);
        if (mappedProviderProxy !== undefined) {
          ruleProvider.proxy = mappedProviderProxy;
        }
      }
    }
  }

  if (compactGroupsEnabled) {
    var keepGroupNames = createNameMap();
    for (var keepName in managedTargetMap) {
      if (hasOwn(managedTargetMap, keepName)) {
        keepGroupNames[managedTargetMap[keepName]] = true;
      }
    }
    // 旧订阅的受管别名可能仍被 listener / tunnel / ntp 引用；这些名称
    // 不属于 originalCustomGroupNames，不能靠关闭压缩来保留，需显式留下。
    var legacyManagedAliases = ["Claude", "Google", "YouTube", "Telegram"];
    for (var legacyAliasIndex = 0; legacyAliasIndex < legacyManagedAliases.length; legacyAliasIndex++) {
      var legacyAliasGroup = findGroup(legacyManagedAliases[legacyAliasIndex]);
      if (legacyAliasGroup) {
        keepGroupNames[legacyAliasGroup.name] = true;
      }
    }

    var compactGroups = [];
    var compactSeen = createNameMap();
    for (var cg = 0; cg < groups.length; cg++) {
      var compactGroup = groups[cg];
      if (compactGroup && keepGroupNames[compactGroup.name] && !compactSeen[compactGroup.name]) {
        compactGroups.push(compactGroup);
        compactSeen[compactGroup.name] = true;
      }
    }
    groups = compactGroups;
  }

  var displayGroupOrder = [
    managedGroups.AI,
    managedGroups.GoogleYouTubeTelegram,
    managedGroups.Exchange,
    managedGroups.US,
    managedGroups.TW,
    managedGroups.SG,
    managedGroups.HK,
    managedGroups.JP,
    managedGroups.UK,
    PROXIES_GROUP
  ];
  var orderedGroups = [];
  var orderedSeen = createNameMap();
  function appendGroupByName(name) {
    if (!name || orderedSeen[name]) {
      return;
    }
    for (var ag = 0; ag < groups.length; ag++) {
      if (groups[ag] && groups[ag].name === name) {
        orderedGroups.push(groups[ag]);
        orderedSeen[name] = true;
        return;
      }
    }
  }
  for (var og = 0; og < displayGroupOrder.length; og++) {
    appendGroupByName(displayGroupOrder[og]);
  }
  for (var rg = 0; rg < groups.length; rg++) {
    if (groups[rg] && groups[rg].name && !orderedSeen[groups[rg].name]) {
      orderedGroups.push(groups[rg]);
      orderedSeen[groups[rg].name] = true;
    }
  }
  groups = orderedGroups;

  // 三层显示模型：业务组、地区组、普通代理 Proxies。机场常见的
  // PROXY / GLOBAL / 订阅更新等是实现细节，保留它们让原始规则继续工作，
  // 但隐藏在代理页，不与核心组并列显示。未命中这些精确名称的自定义组不动，
  // 避免把用户自己的策略入口误判成技术组。
  var technicalGroupPatterns = [
    /^(global|global proxy|proxy|proxies|proxy select|auto|fallback)$/i,
    /^(节点选择|代理|代理选择|手动切换|自动选择|故障转移)$/,
    /^(订阅更新|更新订阅|订阅检测|subscription update|subscription check)$/i
  ];

  function isTechnicalGroupName(name) {
    var groupName = String(name || "").trim();
    for (var patternIndex = 0; patternIndex < technicalGroupPatterns.length; patternIndex++) {
      if (technicalGroupPatterns[patternIndex].test(groupName)) {
        return true;
      }
    }
    return false;
  }

  for (var hiddenGroupIndex = 0; hiddenGroupIndex < groups.length; hiddenGroupIndex++) {
    var hiddenGroup = groups[hiddenGroupIndex];
    if (hiddenGroup && hiddenGroup.name !== PROXIES_GROUP && isTechnicalGroupName(hiddenGroup.name)) {
      hiddenGroup.hidden = true;
    }
  }

  config["proxy-groups"] = groups;

  function splitRuleParts(rule) {
    var parts = [];
    var current = "";
    var depth = 0;
    for (var i = 0; i < rule.length; i++) {
      var character = rule.charAt(i);
      if (character === "(") {
        depth += 1;
      } else if (character === ")" && depth > 0) {
        depth -= 1;
      }
      if (character === "," && depth === 0) {
        parts.push(current);
        current = "";
      } else {
        current += character;
      }
    }
    parts.push(current);
    return parts;
  }

  function rewriteRuleTarget(rule) {
    if (typeof rule !== "string") {
      return rule;
    }
    var parts = splitRuleParts(rule);
    if (parts.length < 2) {
      return rule;
    }
    var ruleType = String(parts[0] || "").toUpperCase();
    var changed = false;
    if (ruleType === "SUB-RULE") {
      return rule;
    }
    if (ruleType === "FINAL") {
      parts[0] = "MATCH";
      ruleType = "MATCH";
      changed = true;
    }
    var targetIndex = ruleType === "MATCH" ? 1 : 2;
    if (parts.length > targetIndex) {
      var mappedTarget = lookupName(managedTargetMap, parts[targetIndex]);
      if (mappedTarget !== undefined) {
        parts[targetIndex] = mappedTarget;
        changed = true;
      }
    }
    return changed ? parts.join(",") : rule;
  }

  // 规则目标兜底：规则可能引用「地区组」（如 Merge.yaml 的 dola.com→SG、面板域名→TW），
  // 而地区组只在订阅里出现对应地区节点时才创建。目标组不存在时 mihomo 会拒绝整份
  // 配置（proxy [SG] not found），用户侧表现为配置完全无法加载。所以把指向「未创建
  // 地区组」的目标改为兜底组并打日志。
  // 只动地区组名义名（HK/JP/SG/TW/US/UK）：订阅自带的其他目标（节点名、自定义组）
  // 不碰 —— 订阅自己的配置错误仍按原样交给内核报错，不静默改写。
  var finalGroupNameSet = createNameMap();
  for (var finalGroupIndex = 0; finalGroupIndex < groups.length; finalGroupIndex++) {
    if (groups[finalGroupIndex] && groups[finalGroupIndex].name) {
      finalGroupNameSet[groups[finalGroupIndex].name] = true;
    }
  }
  var regionNameSet = createNameMap();
  for (var regionNameIndex = 0; regionNameIndex < regionOrder.length; regionNameIndex++) {
    regionNameSet[regionOrder[regionNameIndex]] = true;
  }
  var degradedRuleCount = 0;
  var degradedRegionNames = createNameMap();

  function rewriteMissingRegionTarget(rule) {
    if (typeof rule !== "string") {
      return rule;
    }
    var parts = splitRuleParts(rule);
    if (parts.length < 2) {
      return rule;
    }
    var ruleType = String(parts[0] || "").toUpperCase();
    if (ruleType === "SUB-RULE") {
      return rule;
    }
    var targetIndex = ruleType === "MATCH" || ruleType === "FINAL" ? 1 : 2;
    if (parts.length <= targetIndex) {
      return rule;
    }
    var target = String(parts[targetIndex] || "").trim();
    if (!regionNameSet[target.toUpperCase()] || finalGroupNameSet[target]) {
      return rule;
    }
    parts[targetIndex] = PROXIES_GROUP;
    degradedRuleCount += 1;
    degradedRegionNames[target] = true;
    return parts.join(",");
  }

  var exchangeDomains = [
    "okx.com",
    "okx-dns.com",
    "okx-dns1.com",
    "okx-dns2.com",
    "okx-httpdns.com",
    "okx.ac",
    "okex.com",
    "okex.org",
    "oklink.com",
    "okx.cab",
    "coinall.ltd",
    "ouxyi.cash",
    "bybit.com",
    "bybit-global.com",
    "bybit.biz",
    "bybitglobal.com",
    "bybit.cloud",
    "bybit.ada.support",
    "bycsi.com",
    "bytick.com",
    "binance.com",
    "binance.cloud",
    "binancefuture.com",
    "binance.info",
    "binance.me",
    "binance.us",
    "binanceapi.com",
    "binancecnt.com",
    "bnappzh.co",
    "bnbstatic.com",
    "bnbzh.ac",
    "bntrace.com",
    "saasexch.cc",
    "saasexch.com",
    "binance.vision",
    "bitget.com",
    "bitgetimg.com",
    "bitgetstatic.com",
    "gate.com",
    "gate.io",
    "gateimg.com",
    "kucoin.com",
    "kucoin.plus",
    "kucoin.cloud",
    "mexc.com",
    "mexc.co",
    "mexc.fm",
    "crypto.com",
    "coinbase.com",
    "coinbasecdn.net",
    "kraken.com",
    "krakenassets.com",
    "htx.com",
    "huobi.com",
    "huobi.pro",
    "bingx.com",
    "bitmart.com",
    "bitfinex.com",
    "bitstamp.net",
    "upbit.com"
  ];

  var exchangeDomainSet = createNameMap();
  for (var k = 0; k < exchangeDomains.length; k++) {
    exchangeDomainSet[exchangeDomains[k]] = true;
  }

  function isManagedExchangeRule(rule) {
    if (typeof rule !== "string") {
      return false;
    }
    var parts = splitRuleParts(rule);
    var type = String(parts[0] || "").trim().toUpperCase();
    var domain = String(parts[1] || "").trim().toLowerCase();
    // 仅去重目标是受管 Exchange 组的规则；指向 DIRECT 等其它目标的是用户意图，必须保留
    return type === "DOMAIN-SUFFIX" &&
      exchangeDomainSet[domain] === true &&
      parts.length > 2 &&
      String(parts[2] || "").trim() === managedGroups.Exchange;
  }

  var exchangeRules = [];
  for (var er = 0; er < exchangeDomains.length; er++) {
    exchangeRules.push("DOMAIN-SUFFIX," + exchangeDomains[er] + "," + managedGroups.Exchange);
  }

  function rewriteRuleList(ruleList) {
    if (!Array.isArray(ruleList)) {
      return [];
    }
    var rewrittenRules = [];
    for (var ruleIndex = 0; ruleIndex < ruleList.length; ruleIndex++) {
      rewrittenRules.push(rewriteMissingRegionTarget(rewriteRuleTarget(ruleList[ruleIndex])));
    }
    return rewrittenRules;
  }

  if (subRules && typeof subRules === "object") {
    for (var rewriteSubRuleName in subRules) {
      if (hasOwn(subRules, rewriteSubRuleName) && Array.isArray(subRules[rewriteSubRuleName])) {
        subRules[rewriteSubRuleName] = rewriteRuleList(subRules[rewriteSubRuleName]);
      }
    }
  }

  var rules = Array.isArray(config.rules) ? config.rules : [];
  var cleanedRules = [];
  for (var r = 0; r < rules.length; r++) {
    var rewrittenRule = rewriteMissingRegionTarget(rewriteRuleTarget(rules[r]));
    if (!isManagedExchangeRule(rewrittenRule)) {
      cleanedRules.push(rewrittenRule);
    }
  }

  function isBroadRule(rule) {
    if (typeof rule !== "string") {
      return false;
    }
    var upperRule = rule.toUpperCase();
    var broadRules = [
      "RULE-SET,GFW,",
      "RULE-SET,GREATFIRE,",
      "RULE-SET,TLD-NOT-CN,",
      "RULE-SET,PROXY,",
      "RULE-SET,DIRECT,",
      "RULE-SET,APPLICATIONS,",
      "RULE-SET,CNCIDR,",
      "RULE-SET,CN-DOMAIN,",
      "RULE-SET,CN-IP,",
      "RULE-SET,GLOBAL-DOMAIN,",
      "RULE-SET,TLD-PROXY,",
      "GEOIP,",
      "GEOSITE,",
      "MATCH,",
      "FINAL,"
    ];

    for (var broadIndex = 0; broadIndex < broadRules.length; broadIndex++) {
      if (upperRule.indexOf(broadRules[broadIndex]) === 0) {
        return true;
      }
    }

    return upperRule.indexOf("IP-CIDR,0.0.0.0/0,") === 0 ||
      upperRule.indexOf("IP-CIDR6,::/0,") === 0;
  }

  var insertAt = -1;
  for (var cleanedRuleIndex = 0; cleanedRuleIndex < cleanedRules.length; cleanedRuleIndex++) {
    if (isBroadRule(cleanedRules[cleanedRuleIndex])) {
      insertAt = cleanedRuleIndex;
      break;
    }
  }
  if (insertAt === -1) {
    // 无兜底规则时追加到末尾，与有 MATCH/FINAL 的场景一致：
    // 交易所规则始终位于用户具体规则之后、兜底层之前。
    insertAt = cleanedRules.length;
  }
  cleanedRules.splice.apply(cleanedRules, [insertAt, 0].concat(exchangeRules));
  config.rules = cleanedRules;

  if (degradedRuleCount > 0) {
    console.log("[clash-verge-share-kit] 已将 " + degradedRuleCount + " 条规则的目标改为兜底组 " +
      PROXIES_GROUP + "：这些规则指向的地区组（" + Object.keys(degradedRegionNames).join(" / ") +
      "）在当前订阅里没有对应节点。需要固定到对应地区时，请给订阅补充该地区节点。");
  }

  return config;
}
