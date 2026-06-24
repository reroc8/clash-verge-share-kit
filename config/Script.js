function main(config, profileName) {
  var groups = config["proxy-groups"] || [];
  var groupNames = {};
  for (var i = 0; i < groups.length; i++) {
    groupNames[groups[i].name] = true;
  }

  var exchangeOptions = ["Proxies", "JP", "HK", "SG", "TW", "US", "DIRECT"];
  var availableOptions = [];
  for (var j = 0; j < exchangeOptions.length; j++) {
    var option = exchangeOptions[j];
    if (option === "DIRECT" || groupNames[option]) {
      availableOptions.push(option);
    }
  }

  if (!groupNames.Exchange && availableOptions.length > 0) {
    groups.push({
      name: "Exchange",
      type: "select",
      proxies: availableOptions
    });
  }
  config["proxy-groups"] = groups;

  var exchangeRules = [
    "DOMAIN-SUFFIX,okx.com,Exchange",
    "DOMAIN-SUFFIX,bybit.com,Exchange",
    "DOMAIN-SUFFIX,bybitglobal.com,Exchange",
    "DOMAIN-SUFFIX,bycsi.com,Exchange",
    "DOMAIN-SUFFIX,bytick.com,Exchange",
    "DOMAIN-SUFFIX,binance.com,Exchange",
    "DOMAIN-SUFFIX,binance.info,Exchange",
    "DOMAIN-SUFFIX,binance.me,Exchange",
    "DOMAIN-SUFFIX,bitget.com,Exchange",
    "DOMAIN-SUFFIX,gate.com,Exchange",
    "DOMAIN-SUFFIX,gate.io,Exchange"
  ];

  var existingExchangeRules = {};
  for (var k = 0; k < exchangeRules.length; k++) {
    existingExchangeRules[exchangeRules[k]] = true;
  }

  var rules = config.rules || [];
  var cleanedRules = [];
  for (var r = 0; r < rules.length; r++) {
    if (!existingExchangeRules[rules[r]]) {
      cleanedRules.push(rules[r]);
    }
  }

  var insertAt = cleanedRules.length;
  var broadRules = [
    "RULE-SET,gfw,",
    "RULE-SET,greatfire,",
    "RULE-SET,tld-not-cn,",
    "RULE-SET,proxy,",
    "RULE-SET,direct,",
    "RULE-SET,applications,",
    "MATCH,"
  ];

  for (var x = 0; x < cleanedRules.length; x++) {
    for (var y = 0; y < broadRules.length; y++) {
      if (cleanedRules[x].indexOf(broadRules[y]) === 0) {
        insertAt = x;
        x = cleanedRules.length;
        break;
      }
    }
  }

  cleanedRules.splice.apply(cleanedRules, [insertAt, 0].concat(exchangeRules));
  config.rules = cleanedRules;

  return config;
}
