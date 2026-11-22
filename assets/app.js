/* СТОИТ — статический сайт-гид. Без зависимостей. */
(() => {
  "use strict";

  const $ = (sel, root = document) => root.querySelector(sel);
  const $$ = (sel, root = document) => Array.from(root.querySelectorAll(sel));
  const view = $("#view");
  const headerEl = $("#site-header");
  const footerEl = $("#site-footer");
  const modalRoot = $("#modal-root");
  const toastEl = $("#toast");
  const CACHE_KEY = "stoit.feed.v2";
  const LANG_KEY = "stoit.lang";
  const THEME_KEY = "stoit.theme";
  const SAVED_KEY = "stoit.saved";

  const state = {
    feed: null,
    lang: "ru",
    theme: "dark",
    saved: [],
    filters: { cats: [], moods: [], minPrice: 0, maxPrice: null, q: "", sort: "price" },
    visibleCount: 12,
    refreshing: false,
    server: false,
    plan: null,
    toastTimer: null,
  };

  const I18N = {
    ru: {
      "a11y.skip": "К содержанию",
      "boot.loading": "Собираем Москву…",
      "nav.home": "Сегодня",
      "nav.places": "Места",
      "nav.sources": "Источники",
      "nav.saved": "Моё",
      "brand.sub": "Москва, в которую стоит сходить",
      "meta.home": "СТОИТ — Москва, в которую стоит сходить",
      "warning.prices": "Цены и наличие мест лучше сверять перед выходом — они собраны из открытых источников и могут меняться.",
      "header.updated": "обновлено {when}",
      "header.loading": "загрузка…",
      "header.refresh": "Обновить данные",
      "header.lang": "Сменить язык",
      "header.theme": "Сменить тему",
      "header.menu": "Меню",
      "hero.kicker": "гид по Москве · {n} источников",
      "hero.title": "Москва, в которую <em>стоит</em> сходить.",
      "hero.lead": "Кафе, выставки, игры и прогулки — от бесплатных до особого случая. <b>Честные цены за конкретную услугу</b>, а не «средний чек на всё». Лента обновляется каждый день из {n} источников.",
      "hero.cta1": "Смотреть места",
      "hero.cta2": "План на сегодня",
      "hero.metric.places": "мест и идей",
      "hero.metric.sources": "источников",
      "hero.metric.free": "бесплатно",
      "hero.feature": "выбор дня",
      "hero.open": "Посмотреть",
      "tier.all": "Любой бюджет",
      "tier.free": "Бесплатно",
      "tier.low": "до 300 ₽",
      "tier.mid": "300–700 ₽",
      "tier.high": "700–1500 ₽",
      "tier.premium": "1500+ ₽",
      "tier.unknown": "Цена уточняется",
      "tier.free.sub": "вход и прогулки",
      "tier.low.sub": "кофе и перекус",
      "tier.mid.sub": "вечер без удара",
      "tier.high.sub": "особый случай",
      "tier.premium.sub": "большой повод",
      "tier.unknown.sub": "проверить на месте",
      "cat.food": "Еда",
      "cat.coffee": "Кофе",
      "cat.games": "Игры",
      "cat.antikafe": "Антикафе",
      "cat.active": "Активности",
      "cat.culture": "Культура",
      "cat.walk": "Прогулки",
      "cat.movie": "Кино",
      "cat.event": "События",
      "home.picks.kicker": "на сегодня",
      "home.picks.title": "Выбор дня",
      "home.picks.sub": "Четыре места на разный бюджет — от бесплатного до особого случая.",
      "home.fresh.kicker": "свежее",
      "home.fresh.title": "Из источников",
      "home.fresh.sub": "Что нового появилось в московских каналах и медиа за последние дни.",
      "home.fresh.empty": "Сегодня источники не дали новых материалов. Загляните завтра — или посмотрите подборку мест.",
      "home.all.kicker": "каталог",
      "home.all.title": "Все места",
      "home.all.sub": "Кафе, игры, культура и прогулки. Цена указана за то, что вы реально покупаете.",
      "home.all.cta": "Открыть каталог",
      "home.plan.kicker": "без скуки",
      "home.plan.title": "Соберите план на сегодня",
      "home.plan.sub": "Три остановки в рамках бюджета: поесть, чем заняться и где погулять. Без броней и сложных решений.",
      "home.plan.cta": "Собрать план",
      "places.kicker": "каталог",
      "places.title": "Места и идеи",
      "places.sub": "Фильтруйте по бюджету, категории и настроению. Цены — за конкретную услугу.",
      "filters.title": "Фильтры",
      "filters.budget": "Бюджет",
      "filters.category": "Категория",
      "filters.mood": "Настроение",
      "filters.multi": "можно несколько",
      "filters.customBudget": "Свой бюджет",
      "filters.perPerson": "на человека",
      "filters.reset": "Сбросить фильтры",
      "filters.all": "Все",
      "search.placeholder": "Найти место, район или идею…",
      "sort.label": "Сортировка",
      "sort.price": "Сначала дешёвые",
      "sort.rating": "По рейтингу",
      "sort.name": "По названию",
      "sort.new": "Сначала новые",
      "results.count": "{n} мест",
      "results.of": "из {n}",
      "results.more": "Показать ещё",
      "results.none": "Ничего не нашлось",
      "results.noneTitle": "Ничего не нашлось",
      "results.noneText": "Попробуйте ослабить фильтры или поискать другое слово.",
      "results.reset": "Сбросить",
      "card.save": "Сохранить",
      "card.saved": "В сохранённом",
      "card.details": "Подробнее",
      "price.free": "Бесплатно",
      "price.unknown": "цена в источнике",
      "price.inSource": "цена в источнике",
      "price.tbd": "цена уточняется",
      "price.approx": "ориентировочно",
      "price.unit.visit": "за визит",
      "price.unit.entry": "вход",
      "price.unit.hour": "за час",
      "price.unit.person": "с человека",
      "price.unit.ticket": "за билет",
      "price.unit.average": "средний чек",
      "price.unit.drink": "за напиток",
      "price.unit.time": "за время",
      "detail.back": "Назад в каталог",
      "detail.about": "Почему стоит",
      "detail.get": "Что получите",
      "detail.withWhom": "С кем идти",
      "detail.approx": "Цена уточняется",
      "detail.tip": "Совет",
      "detail.deal": "Выгодно",
      "detail.map": "На карте",
      "detail.share": "Поделиться",
      "detail.save": "Сохранить",
      "detail.saved": "Сохранено",
      "detail.similar": "Похожие места",
      "detail.note": "Цены и наличие мест лучше сверять перед выходом — они собраны из открытых источников и могут меняться. Перед выходом сверьтесь с картой или сайтом заведения.",
      "detail.district": "Район",
      "detail.metro": "Метро",
      "detail.address": "Адрес",
      "detail.hours": "Часы",
      "detail.company": "Компания",
      "detail.rating": "Рейтинг",
      "detail.source": "Источник",
      "detail.priceFor": "Цена",
      "detail.badge": "Особенность",
      "idea.kicker": "из источника",
      "idea.back": "К источникам",
      "idea.original": "Открыть источник",
      "idea.related": "Места по теме",
      "idea.translated": "Машинный перевод",
      "idea.published": "Опубликовано",
      "idea.price": "Цена",
      "idea.noPrice": "Цена не указана — смотрите в источнике",
      "sources.kicker": "как обновляется",
      "sources.title": "Источники, один гид",
      "sources.sub": "Telegram-каналы, городские медиа, официальная афиша и обсуждения. Каждый день сайт собирает свежие идеи и проверяет цены.",
      "sources.updated": "Обновлено",
      "sources.next": "Следующее обновление",
      "sources.active": "Источников в норме",
      "sources.materials": "Материалов в ленте",
      "sources.refresh": "Обновить сейчас",
      "sources.refreshing": "Обновляем…",
      "sources.items": "{n} материалов",
      "sources.last": "последняя синхронизация",
      "sources.visit": "Открыть",
      "sources.status.ok": "онлайн",
      "sources.status.cached": "из кэша",
      "sources.status.error": "недоступен",
      "sources.howTitle": "Как это работает",
      "sources.how1.title": "Собираем",
      "sources.how1.text": "Все доступные ленты: Telegram, городские медиа, Mos.ru, обсуждения и Google News. Сборщик читает их и оставляет только места, события и идеи.",
      "sources.how2.title": "Проверяем",
      "sources.how2.text": "Убираем новости, рекламу и другие города. Цену показываем за конкретную услугу: час игры, билет, вход или средний чек.",
      "sources.how3.title": "Обновляем",
      "sources.how3.text": "Данные обновляются раз в день. Если источник недоступен, показываем кэш, поэтому лента не пропадает.",
      "sources.note": "Лента обновляется автоматически. Ручное обновление запускает сборщик на локальном сервере.",
      "sources.empty": "нет материалов",
      "kind.telegram": "Telegram",
      "kind.media": "Медиа",
      "kind.official": "Официально",
      "kind.community": "Обсуждения",
      "kind.aggregator": "Агрегатор",
      "kind.social": "Instagram",
      "kind.catalog": "Каталог",
      "sourceGroup.community": "Обсуждения и советы",
      "sourceGroup.telegram": "Telegram-каналы",
      "sourceGroup.social": "Instagram",
      "sourceGroup.media": "Городские медиа",
      "sourceGroup.official": "Официальные",
      "sourceGroup.catalog": "Каталоги мест",
      "sourceGroup.aggregator": "Подборки и агрегаторы",
      "party.any": "Любая",
      "party.friends": "С друзьями",
      "party.date": "Свидание",
      "party.solo": "Один",
      "party.family": "С детьми",
      "saved.kicker": "ваше",
      "saved.title": "Сохранённые места",
      "saved.sub": "Список, который всегда под рукой. Можно собрать план на сегодня прямо из него.",
      "saved.emptyTitle": "Здесь пока пусто",
      "saved.emptyText": "Нажмите на закладку на карточке места — и оно появится здесь. Сохранённые места остаются в браузере, даже без интернета.",
      "saved.cta": "Смотреть места",
      "saved.plan": "Собрать план",
      "saved.count": "{n} сохранено",
      "plan.kicker": "план на сегодня",
      "plan.title": "Три остановки, один бюджет",
      "plan.sub": "Выберите бюджет — соберём маршрут из еды, занятия и прогулки. Каждый шаг можно открыть и посмотреть детали.",
      "plan.budget": "Бюджет",
      "plan.custom": "Свой бюджет",
      "plan.any": "Без ограничений",
      "plan.party": "С кем идём",
      "plan.total": "Итого",
      "plan.perPerson": "на человека",
      "plan.within": "укладывается в бюджет",
      "plan.over": "чуть выше бюджета",
      "plan.again": "Другой вариант",
      "plan.close": "Готово",
      "plan.step": "Шаг {n}",
      "plan.empty": "Не получилось собрать план — попробуйте другой бюджет.",
      "footer.about": "СТОИТ — независимый гид по Москве. Кафе, выставки, игры и прогулки с честной ценой за конкретную услугу. Без рекламы и партнёрских ссылок.",
      "footer.nav": "Навигация",
      "footer.sources": "Источники",
      "footer.note": "Цены собраны из открытых источников и могут меняться. Перед выходом сверьтесь с картой или сайтом заведения.",
      "footer.rights": "Сделано для Москвы.",
      "footer.osm": "Картографические данные: © OpenStreetMap contributors",
      "footer.updated": "Данные обновлены",
      "footer.allSources": "Все источники",
      "time.now": "только что",
      "time.minAgo": "{n} мин назад",
      "time.hourAgo": "{n} ч назад",
      "time.dayAgo": "{n} дн назад",
      "time.todayAt": "сегодня, {time}",
      "time.updated": "обновлено {when}",
      "toast.saved": "Добавлено в сохранённые",
      "toast.removed": "Удалено из сохранённых",
      "toast.copied": "Ссылка скопирована",
      "toast.refreshed": "Данные обновлены",
      "toast.refreshStarted": "Обновление запущено. Новая версия появится через 1–3 минуты.",
      "toast.cooldown": "Обновление уже запускалось. Следующее — через {min} мин.",
      "toast.refreshTimeout": "Обновление запущено, но ещё не готово. Проверьте через пару минут.",
      "toast.static": "Новые данные появятся после следующей синхронизации",
      "toast.error": "Не получилось обновить. Попробуйте ещё раз.",
      "offline.text": "Нет соединения — показываем сохранённую версию.",
      "error.title": "Не удалось загрузить данные",
      "error.text": "Проверьте соединение и попробуйте ещё раз. Если сайт открыт локально, запустите сервер обновления.",
      "error.retry": "Повторить",
      "common.close": "Закрыть",
      "common.all": "Все",
      "common.more": "Ещё",
      "common.min": "мин",
      "common.from": "от",
      "day.0": "вс",
      "day.1": "пн",
      "day.2": "вт",
      "day.3": "ср",
      "day.4": "чт",
      "day.5": "пт",
      "day.6": "сб",
    },
    en: {
      "a11y.skip": "Skip to content",
      "boot.loading": "Assembling Moscow…",
      "nav.home": "Today",
      "nav.places": "Places",
      "nav.sources": "Sources",
      "nav.saved": "Saved",
      "brand.sub": "Moscow worth going out for",
      "meta.home": "STOIT — Moscow worth going out for",
      "warning.prices": "Prices and availability are best checked before you go — they come from public sources and may change.",
      "header.updated": "updated {when}",
      "header.loading": "loading…",
      "header.refresh": "Refresh data",
      "header.lang": "Switch language",
      "header.theme": "Switch theme",
      "header.menu": "Menu",
      "hero.kicker": "Moscow guide · {n} sources",
      "hero.title": "Moscow <em>worth</em> going out for.",
      "hero.lead": "Cafes, exhibitions, games and walks — from free to special occasion. <b>Honest prices for what you actually get</b>, not an average bill for everything. The feed updates daily from {n} sources.",
      "hero.cta1": "Browse places",
      "hero.cta2": "Plan today",
      "hero.metric.places": "places & ideas",
      "hero.metric.sources": "sources",
      "hero.metric.free": "free",
      "hero.feature": "pick of the day",
      "hero.open": "Take a look",
      "tier.all": "Any budget",
      "tier.free": "Free",
      "tier.low": "under ₽300",
      "tier.mid": "₽300–700",
      "tier.high": "₽700–1500",
      "tier.premium": "₽1500+",
      "tier.unknown": "Price TBD",
      "tier.free.sub": "entry & walks",
      "tier.low.sub": "coffee & a bite",
      "tier.mid.sub": "an easy evening",
      "tier.high.sub": "special occasion",
      "tier.premium.sub": "big occasion",
      "tier.unknown.sub": "check on site",
      "cat.food": "Food",
      "cat.coffee": "Coffee",
      "cat.games": "Games",
      "cat.antikafe": "Anti-cafe",
      "cat.active": "Activities",
      "cat.culture": "Culture",
      "cat.walk": "Walks",
      "cat.movie": "Cinema",
      "cat.event": "Events",
      "home.picks.kicker": "for today",
      "home.picks.title": "Today's picks",
      "home.picks.sub": "Four places across budgets — from free to a proper occasion.",
      "home.fresh.kicker": "fresh",
      "home.fresh.title": "From the sources",
      "home.fresh.sub": "What has just appeared in Moscow channels and media over the past few days.",
      "home.fresh.empty": "No new material today. Come back tomorrow — or browse the places collection.",
      "home.all.kicker": "catalogue",
      "home.all.title": "All places",
      "home.all.sub": "Cafes, games, culture and walks. The price is for what you actually buy.",
      "home.all.cta": "Open the catalogue",
      "home.plan.kicker": "no boredom",
      "home.plan.title": "Build today's plan",
      "home.plan.sub": "Three stops within a budget: eat, do something, take a walk. No bookings, no overthinking.",
      "home.plan.cta": "Build a plan",
      "places.kicker": "catalogue",
      "places.title": "Places & ideas",
      "places.sub": "Filter by budget, category and mood. Prices are for a specific service.",
      "filters.title": "Filters",
      "filters.budget": "Budget",
      "filters.category": "Category",
      "filters.mood": "Mood",
      "filters.multi": "pick several",
      "filters.customBudget": "Custom budget",
      "filters.perPerson": "per person",
      "filters.reset": "Reset filters",
      "filters.all": "All",
      "search.placeholder": "Find a place, district or idea…",
      "sort.label": "Sort",
      "sort.price": "Cheapest first",
      "sort.rating": "Top rated",
      "sort.name": "By name",
      "sort.new": "Newest first",
      "results.count": "{n} places",
      "results.of": "of {n}",
      "results.more": "Show more",
      "results.none": "Nothing found",
      "results.noneTitle": "Nothing found",
      "results.noneText": "Try loosening the filters or searching for another word.",
      "results.reset": "Reset",
      "card.save": "Save",
      "card.saved": "Saved",
      "card.details": "Details",
      "price.free": "Free",
      "price.unknown": "price in source",
      "price.inSource": "price in source",
      "price.tbd": "price TBD",
      "price.approx": "approximate",
      "price.unit.visit": "per visit",
      "price.unit.entry": "entry",
      "price.unit.hour": "per hour",
      "price.unit.person": "per person",
      "price.unit.ticket": "per ticket",
      "price.unit.average": "average bill",
      "price.unit.drink": "per drink",
      "price.unit.time": "for time",
      "detail.back": "Back to catalogue",
      "detail.about": "Why it's worth it",
      "detail.get": "What you get",
      "detail.withWhom": "Who to bring",
      "detail.approx": "Price TBD",
      "detail.tip": "Tip",
      "detail.deal": "Good deal",
      "detail.map": "On the map",
      "detail.share": "Share",
      "detail.save": "Save",
      "detail.saved": "Saved",
      "detail.similar": "Similar places",
      "detail.note": "Prices and availability are best checked before you go — they come from public sources and may change. Check the map or venue website first.",
      "detail.district": "District",
      "detail.metro": "Metro",
      "detail.address": "Address",
      "detail.hours": "Hours",
      "detail.company": "Company",
      "detail.rating": "Rating",
      "detail.source": "Source",
      "detail.priceFor": "Price",
      "detail.badge": "Highlight",
      "idea.kicker": "from the source",
      "idea.back": "Back to sources",
      "idea.original": "Open the source",
      "idea.related": "Places on the topic",
      "idea.translated": "Machine translation",
      "idea.published": "Published",
      "idea.price": "Price",
      "idea.noPrice": "No price given — check the source",
      "sources.kicker": "how it updates",
      "sources.title": "Many sources, one guide",
      "sources.sub": "Telegram channels, city media, the official programme and community feeds. Every day the site collects fresh ideas and checks prices.",
      "sources.updated": "Updated",
      "sources.next": "Next update",
      "sources.active": "Sources online",
      "sources.materials": "Items in the feed",
      "sources.refresh": "Refresh now",
      "sources.refreshing": "Refreshing…",
      "sources.items": "{n} items",
      "sources.last": "last sync",
      "sources.visit": "Open",
      "sources.status.ok": "online",
      "sources.status.cached": "cached",
      "sources.status.error": "unavailable",
      "sources.howTitle": "How it works",
      "sources.how1.title": "Collect",
      "sources.how1.text": "Every available feed: Telegram, city media, Mos.ru, community channels and Google News. The collector keeps only places, events and ideas.",
      "sources.how2.title": "Check",
      "sources.how2.text": "News, ads and other cities are filtered out. Prices are shown for a specific service: an hour of play, a ticket, entry or an average bill.",
      "sources.how3.title": "Update",
      "sources.how3.text": "Data refreshes once a day. If a source is down, the cache is used so the feed never disappears.",
      "sources.note": "The feed updates automatically. Manual refresh runs the collector on the local server.",
      "sources.empty": "no items",
      "kind.telegram": "Telegram",
      "kind.media": "Media",
      "kind.official": "Official",
      "kind.community": "Community",
      "kind.aggregator": "Aggregator",
      "kind.social": "Instagram",
      "kind.catalog": "Catalogue",
      "sourceGroup.community": "Discussions & tips",
      "sourceGroup.telegram": "Telegram channels",
      "sourceGroup.social": "Instagram",
      "sourceGroup.media": "City media",
      "sourceGroup.official": "Official",
      "sourceGroup.catalog": "Venue catalogues",
      "sourceGroup.aggregator": "Guides & aggregators",
      "party.any": "Anyone",
      "party.friends": "With friends",
      "party.date": "Date",
      "party.solo": "Solo",
      "party.family": "With kids",
      "saved.kicker": "yours",
      "saved.title": "Saved places",
      "saved.sub": "A list that is always at hand. Build today's plan straight from it.",
      "saved.emptyTitle": "Nothing here yet",
      "saved.emptyText": "Tap the bookmark on a place card and it will appear here. Saved places stay in your browser, even offline.",
      "saved.cta": "Browse places",
      "saved.plan": "Build a plan",
      "saved.count": "{n} saved",
      "plan.kicker": "today's plan",
      "plan.title": "Three stops, one budget",
      "plan.sub": "Choose a budget and we will build a route with food, something to do and a walk. Open any step for details.",
      "plan.budget": "Budget",
      "plan.custom": "Custom budget",
      "plan.any": "No limit",
      "plan.party": "Who's coming",
      "plan.total": "Total",
      "plan.perPerson": "per person",
      "plan.within": "within budget",
      "plan.over": "slightly over budget",
      "plan.again": "Another option",
      "plan.close": "Done",
      "plan.step": "Stop {n}",
      "plan.empty": "Could not build a plan — try another budget.",
      "footer.about": "STOIT is an independent Moscow guide. Cafes, exhibitions, games and walks with an honest price for what you get. No ads, no affiliate links.",
      "footer.nav": "Navigation",
      "footer.sources": "Sources",
      "footer.note": "Prices come from public sources and may change. Check the map or venue website before you go.",
      "footer.rights": "Made for Moscow.",
      "footer.osm": "Map data: © OpenStreetMap contributors",
      "footer.updated": "Data updated",
      "footer.allSources": "All sources",
      "time.now": "just now",
      "time.minAgo": "{n} min ago",
      "time.hourAgo": "{n} h ago",
      "time.dayAgo": "{n} d ago",
      "time.todayAt": "today, {time}",
      "time.updated": "updated {when}",
      "toast.saved": "Added to saved",
      "toast.removed": "Removed from saved",
      "toast.copied": "Link copied",
      "toast.refreshed": "Data refreshed",
      "toast.refreshStarted": "Refresh started. The new version will appear in 1–3 minutes.",
      "toast.cooldown": "Refresh was already started. Next one in {min} min.",
      "toast.refreshTimeout": "Refresh started but is not ready yet. Check again in a couple of minutes.",
      "toast.static": "New data will appear after the next sync",
      "toast.error": "Could not refresh. Try again.",
      "offline.text": "No connection — showing the saved version.",
      "error.title": "Could not load the data",
      "error.text": "Check your connection and try again. If you are running the site locally, start the update server.",
      "error.retry": "Try again",
      "common.close": "Close",
      "common.all": "All",
      "common.more": "More",
      "common.min": "min",
      "common.from": "from",
      "day.0": "Sun",
      "day.1": "Mon",
      "day.2": "Tue",
      "day.3": "Wed",
      "day.4": "Thu",
      "day.5": "Fri",
      "day.6": "Sat",
    },
  };

  const CATEGORIES = {
    food: "🍲",
    coffee: "☕️",
    games: "🎮",
    antikafe: "🛋",
    active: "🎳",
    culture: "🖼",
    walk: "🌳",
    movie: "🎬",
    event: "✨",
  };

  const TIERS = [
    { id: "free", min: 0, max: 0 },
    { id: "low", min: 1, max: 300 },
    { id: "mid", min: 301, max: 700 },
    { id: "high", min: 701, max: 1500 },
    { id: "premium", min: 1501, max: Infinity },
  ];

  const ICONS = {
    arrow: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12h14"/><path d="m13 6 6 6-6 6"/></svg>',
    up: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M7 17 17 7"/><path d="M8 7h9v9"/></svg>',
    search: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" aria-hidden="true"><circle cx="11" cy="11" r="7"/><path d="m20 20-4-4"/></svg>',
    bookmark: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M6 4h12v17l-6-4-6 4z"/></svg>',
    bookmarkFill: '<svg viewBox="0 0 24 24" fill="currentColor" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round" aria-hidden="true"><path d="M6 4h12v17l-6-4-6 4z"/></svg>',
    share: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="18" cy="5" r="3"/><circle cx="6" cy="12" r="3"/><circle cx="18" cy="19" r="3"/><path d="m8.6 10.5 6.8-4"/><path d="m8.6 13.5 6.8 4"/></svg>',
    map: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M20 10c0 5-8 11-8 11S4 15 4 10a8 8 0 1 1 16 0Z"/><circle cx="12" cy="10" r="2.6"/></svg>',
    pin: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M20 10c0 5-8 11-8 11S4 15 4 10a8 8 0 1 1 16 0Z"/><circle cx="12" cy="10" r="2.6"/></svg>',
    metro: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 19V6l7 7 7-7v13"/><path d="M5 19h14"/></svg>',
    clock: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/></svg>',
    users: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.9"/><path d="M16 3.1a4 4 0 0 1 0 7.8"/></svg>',
    star: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m12 3 2.8 5.7 6.2.9-4.5 4.4 1 6.2-5.5-2.9-5.5 2.9 1-6.2L3 9.6l6.2-.9z"/></svg>',
    close: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" aria-hidden="true"><path d="M6 6l12 12M18 6 6 18"/></svg>',
    refresh: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M20 11a8 8 0 1 0-2.3 5.7"/><path d="M20 4v7h-7"/></svg>',
    sun: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" aria-hidden="true"><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/></svg>',
    moon: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8Z"/></svg>',
    globe: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" aria-hidden="true"><circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3a15 15 0 0 1 0 18M12 3a15 15 0 0 0 0 18"/></svg>',
    menu: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" aria-hidden="true"><path d="M4 7h16M4 12h16M4 17h16"/></svg>',
    rss: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" aria-hidden="true"><path d="M4 11a9 9 0 0 1 9 9M4 4a16 16 0 0 1 16 16"/><circle cx="5" cy="19" r="1.4" fill="currentColor"/></svg>',
    spark: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m12 3 1.7 5.3L19 10l-5.3 1.7L12 17l-1.7-5.3L5 10l5.3-1.7z"/><path d="M19 16l.7 2.3L22 19l-2.3.7L19 22l-.7-2.3L16 19l2.3-.7z"/></svg>',
    offline: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" aria-hidden="true"><path d="M2 2l20 20"/><path d="M8.5 16.5a5 5 0 0 1 7 0"/><path d="M5 13a10 10 0 0 1 4-2.4"/><path d="M15 10.6A10 10 0 0 1 19 13"/><path d="M2 8.8A15 15 0 0 1 8 5.7"/><path d="M16 5.7a15 15 0 0 1 6 3.1"/></svg>',
    check: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m5 12 5 5 9-10"/></svg>',
    chevron: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m6 9 6 6 6-6"/></svg>',
  };

  function icon(name) {
    return ICONS[name] || "";
  }

  function t(key, vars) {
    let value = (I18N[state.lang] && I18N[state.lang][key]) || (I18N.ru && I18N.ru[key]) || key;
    if (vars) {
      Object.keys(vars).forEach((k) => {
        value = value.replace(new RegExp("\\{" + k + "\\}", "g"), String(vars[k]));
      });
    }
    return value;
  }

  function loc(value) {
    if (value == null) return "";
    if (typeof value === "string") return value;
    return value[state.lang] || value.ru || value.en || "";
  }

  function esc(value) {
    return String(value == null ? "" : value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;");
  }

  function num(value) {
    return new Intl.NumberFormat(state.lang === "ru" ? "ru-RU" : "en-GB").format(value);
  }

  function money(value) {
    if (value === 0) return t("price.free");
    return state.lang === "ru" ? num(value) + " ₽" : "₽" + num(value);
  }

  function categoryLabel(cat) {
    return t("cat." + (CATEGORIES[cat] ? cat : "event"));
  }

  function categoryEmoji(cat) {
    return CATEGORIES[cat] || CATEGORIES.event;
  }

  function placeEmoji(place) {
    return place.emoji || categoryEmoji(place.category);
  }

  function showBadge(place) {
    const badge = loc(place.badge).toLowerCase();
    if (!badge) return false;
    const tier = tierLabel(tierOf(place.price)).toLowerCase();
    return badge !== tier;
  }

  function tierOf(price) {
    if (price == null) return "unknown";
    if (price === 0) return "free";
    if (price <= 300) return "low";
    if (price <= 700) return "mid";
    if (price <= 1500) return "high";
    return "premium";
  }

  function tierLabel(tier) {
    return t("tier." + tier);
  }

  function placeUnit(place) {
    return loc(place.priceUnit) || t("price.unit." + (place.category === "food" ? "average" : place.category === "movie" ? "ticket" : place.category === "games" || place.category === "active" ? "visit" : "entry"));
  }

  function priceText(place) {
    if (place.price == null) return t("price.tbd");
    if (place.price === 0) return t("price.free");
    const base = money(place.price);
    return place.priceApprox ? "≈ " + base : base;
  }

  function companyShort(place) {
    return loc(place.company).replace(/\s*(человека|компания|people|group)$/i, "").trim();
  }

  function dateKey(d = new Date()) {
    return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0");
  }

  function hashString(str) {
    let h = 2166136261;
    for (let i = 0; i < str.length; i += 1) {
      h ^= str.charCodeAt(i);
      h = Math.imul(h, 16777619);
    }
    return h >>> 0;
  }

  function mulberry32(seed) {
    let a = seed >>> 0;
    return function random() {
      a += 0x6d2b79f5;
      let t = a;
      t = Math.imul(t ^ (t >>> 15), t | 1);
      t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }

  function shuffle(items, rng) {
    const arr = items.slice();
    for (let i = arr.length - 1; i > 0; i -= 1) {
      const j = Math.floor(rng() * (i + 1));
      [arr[i], arr[j]] = [arr[j], arr[i]];
    }
    return arr;
  }

  function parseRoute() {
    const raw = (location.hash || "#/").replace(/^#\/?/, "");
    const [pathPart, queryPart] = raw.split("?");
    const parts = pathPart.split("/").filter(Boolean).map((p) => decodeURIComponent(p));
    return { path: "/" + parts.join("/"), parts, params: new URLSearchParams(queryPart || "") };
  }

  function currentSection() {
    return parseRoute().parts[0] || "home";
  }

  function fmtDateTime(iso) {
    if (!iso) return "";
    const d = new Date(iso);
    if (Number.isNaN(d.getTime())) return "";
    return new Intl.DateTimeFormat(state.lang === "ru" ? "ru-RU" : "en-GB", {
      day: "numeric",
      month: "long",
      hour: "2-digit",
      minute: "2-digit",
    }).format(d);
  }

  function fmtShort(iso) {
    if (!iso) return "";
    const d = new Date(iso);
    if (Number.isNaN(d.getTime())) return "";
    const now = new Date();
    const sameDay = d.getFullYear() === now.getFullYear() && d.getMonth() === now.getMonth() && d.getDate() === now.getDate();
    if (sameDay) {
      return new Intl.DateTimeFormat(state.lang === "ru" ? "ru-RU" : "en-GB", { hour: "2-digit", minute: "2-digit" }).format(d);
    }
    return new Intl.DateTimeFormat(state.lang === "ru" ? "ru-RU" : "en-GB", { day: "numeric", month: "short" }).format(d);
  }

  function relative(iso) {
    if (!iso) return "";
    const d = new Date(iso);
    const diff = Math.max(0, Date.now() - d.getTime()) / 1000;
    if (diff < 90) return t("time.now");
    if (diff < 3600) return t("time.minAgo", { n: Math.round(diff / 60) });
    if (diff < 86400) return t("time.hourAgo", { n: Math.round(diff / 3600) });
    if (diff < 86400 * 7) return t("time.dayAgo", { n: Math.round(diff / 86400) });
    return fmtShort(iso);
  }

  function updatedText() {
    if (!state.feed || !state.feed.updatedAt) return t("header.loading");
    return t("header.updated", { when: fmtShort(state.feed.updatedAt) });
  }

  function normalizeText(value) {
    return String(value || "").toLowerCase().replace(/ё/g, "е").replace(/[^\p{L}\p{N}]+/gu, " ").trim();
  }

  function placeSearchText(place) {
    const values = [];
    ["name", "hook", "about", "district", "metro", "address"].forEach((key) => {
      if (place[key] && typeof place[key] === "object") {
        values.push(place[key].ru || "", place[key].en || "");
      }
    });
    if (place.tags) values.push((place.tags.ru || []).join(" "), (place.tags.en || []).join(" "));
    return normalizeText(values.join(" "));
  }

  function tagPairs() {
    if (!state.feed) return [];
    const map = new Map();
    state.feed.places.forEach((place) => {
      const ru = (place.tags && place.tags.ru) || [];
      const en = (place.tags && place.tags.en) || [];
      ru.forEach((tag, i) => {
        if (!map.has(tag)) map.set(tag, { ru: tag, en: en[i] || tag, count: 0 });
        map.get(tag).count += 1;
      });
    });
    return Array.from(map.values()).sort((a, b) => b.count - a.count);
  }

  function tierCounts() {
    const counts = { free: 0, low: 0, mid: 0, high: 0, premium: 0, unknown: 0 };
    (state.feed ? state.feed.places : []).forEach((place) => {
      counts[tierOf(place.price)] += 1;
    });
    return counts;
  }

  function dailyPicks(count = 4) {
    if (!state.feed || !state.feed.places.length) return [];
    const rng = mulberry32(hashString(dateKey()));
    const pools = { free: [], low: [], mid: [], high: [], premium: [] };
    state.feed.places.forEach((place) => pools[tierOf(place.price)].push(place));
    const order = shuffle(["mid", "low", "high", "free", "premium"], rng);
    const picks = [];
    const used = new Set();
    for (const tier of order) {
      const pool = shuffle(pools[tier], rng);
      const found = pool.find((p) => !used.has(p.id));
      if (found) {
        used.add(found.id);
        picks.push(found);
      }
      if (picks.length >= count) break;
    }
    if (picks.length < count) {
      const rest = shuffle(state.feed.places, rng).filter((p) => !used.has(p.id));
      picks.push(...rest.slice(0, count - picks.length));
    }
    return picks;
  }

  function previewPlaces(count = 6) {
    if (!state.feed) return [];
    const rng = mulberry32(hashString(dateKey() + "|all"));
    return shuffle(state.feed.places, rng).slice(0, count);
  }

  function homeSignals(count = 5) {
    if (!state.feed) return [];
    const picked = [];
    const perSource = {};
    for (const signal of state.feed.signals) {
      const used = perSource[signal.sourceId] || 0;
      if (used >= 2) continue;
      picked.push(signal);
      perSource[signal.sourceId] = used + 1;
      if (picked.length >= count) break;
    }
    if (picked.length < count) {
      const ids = new Set(picked.map((s) => s.id));
      for (const signal of state.feed.signals) {
        if (ids.has(signal.id)) continue;
        picked.push(signal);
        if (picked.length >= count) break;
      }
    }
    return picked;
  }

  function priceFilteredPlace(place, filters) {
    if (place.price == null) return filters.minPrice === 0 && filters.maxPrice == null;
    if (place.price < filters.minPrice) return false;
    if (filters.maxPrice != null && place.price > filters.maxPrice) return false;
    return true;
  }

  function filterCandidates(options = {}) {
    if (!state.feed) return [];
    const f = state.filters;
    const words = f.q.trim() ? normalizeText(f.q).split(" ").filter(Boolean) : [];
    return state.feed.places.filter((p) => {
      if (!priceFilteredPlace(p, f)) return false;
      if (!options.ignoreCats && f.cats.length && !f.cats.includes(p.category)) return false;
      if (!options.ignoreMoods && f.moods.length) {
        const tags = (p.tags && p.tags.ru) || [];
        if (!f.moods.some((m) => tags.includes(m))) return false;
      }
      if (words.length) {
        const haystack = placeSearchText(p);
        if (!words.every((word) => haystack.includes(word))) return false;
      }
      return true;
    });
  }

  function filteredPlaces() {
    const list = filterCandidates();
    const f = state.filters;
    if (f.sort === "price") {
      const priceOf = (p) => (p.price == null ? Infinity : p.price);
      list.sort((a, b) => priceOf(a) - priceOf(b) || (b.rating || 0) - (a.rating || 0));
    } else if (f.sort === "rating") {
      list.sort((a, b) => (b.rating || 0) - (a.rating || 0) || (a.price == null ? Infinity : a.price) - (b.price == null ? Infinity : b.price));
    } else if (f.sort === "name") {
      list.sort((a, b) => loc(a.name).localeCompare(loc(b.name), state.lang === "ru" ? "ru" : "en"));
    }
    return list;
  }

  function facetCategoryCounts() {
    const base = filterCandidates({ ignoreCats: true });
    const counts = { all: base.length };
    base.forEach((p) => { counts[p.category] = (counts[p.category] || 0) + 1; });
    return counts;
  }

  function facetMoodCounts() {
    const base = filterCandidates({ ignoreMoods: true });
    const counts = { all: base.length };
    base.forEach((p) => {
      ((p.tags && p.tags.ru) || []).forEach((tag) => { counts[tag] = (counts[tag] || 0) + 1; });
    });
    return counts;
  }

  function planHistory() {
    try {
      const raw = JSON.parse(localStorage.getItem("stoit.planHistory") || "[]");
      const cutoff = Date.now() - 14 * 86400000;
      return Array.isArray(raw) ? raw.filter((x) => x && x.at > cutoff && Array.isArray(x.ids)) : [];
    } catch (_) {
      return [];
    }
  }

  function rememberPlan(steps) {
    if (!steps || !steps.length) return;
    const history = planHistory();
    history.push({ at: Date.now(), ids: steps.map((p) => p.id) });
    try { localStorage.setItem("stoit.planHistory", JSON.stringify(history.slice(-30))); } catch (_) {}
  }

  function recentPlanIds() {
    const cutoff = Date.now() - 7 * 86400000;
    const set = new Set();
    planHistory().forEach((entry) => {
      if (entry.at > cutoff) entry.ids.forEach((id) => set.add(id));
    });
    return set;
  }

  function matchesParty(place, party) {
    if (!party || party === "any") return true;
    const tags = (place.tags && place.tags.ru) || [];
    if (party === "friends") return tags.includes("с друзьями") || tags.includes("на компанию") || tags.includes("весело");
    if (party === "date") return tags.includes("свидание");
    if (party === "family") return tags.includes("с детьми");
    if (party === "solo") return !tags.includes("на компанию") && !tags.includes("с детьми");
    return true;
  }

  function buildPlan(budget, attempt, party = "any", nonce = 0) {
    if (!state.feed) return null;
    const rng = mulberry32(hashString(dateKey() + "|" + budget + "|" + party + "|" + attempt + "|" + nonce));
    const groups = [
      ["food", "coffee"],
      ["games", "active", "culture", "movie"],
      ["walk", "culture"],
    ];
    const recent = recentPlanIds();
    let best = null;
    for (let tries = 0; tries < 520; tries += 1) {
      let total = 0;
      const used = new Set();
      const steps = [];
      let failed = false;
      for (let g = 0; g < groups.length; g += 1) {
        const cap = budget > 0 ? budget - total : Infinity;
        let pool = state.feed.places.filter((p) => groups[g].includes(p.category) && !used.has(p.id) && p.price != null && p.price <= cap);
        const partyPool = party === "any" ? pool : pool.filter((p) => matchesParty(p, party));
        if (partyPool.length) pool = partyPool;
        const fresh = pool.filter((p) => !recent.has(p.id));
        if (fresh.length >= 2) pool = fresh;
        if (!pool.length && g === 2) break;
        if (!pool.length) {
          failed = true;
          break;
        }
        const pick = pool[Math.floor(rng() * pool.length)];
        used.add(pick.id);
        steps.push(pick);
        total += pick.price;
      }
      if (failed || steps.length < 2) continue;
      const variety = new Set(steps.map((p) => p.category)).size;
      const rating = steps.reduce((sum, p) => sum + (p.rating || 4), 0);
      const score = rating + variety * 1.7 + rng() * 0.6 + (budget > 0 && total <= budget ? 0.8 : 0);
      if (!best || score > best.score) best = { steps, total, score };
    }
    if (!best) {
      const sorted = state.feed.places.filter((p) => p.price != null).sort((a, b) => a.price - b.price);
      const free = sorted.filter((p) => p.price === 0).slice(0, 2);
      best = { steps: free, total: 0, score: 0 };
    }
    return best;
  }

  function savedPlaces() {
    if (!state.feed) return [];
    const set = new Set(state.saved);
    return state.feed.places.filter((p) => set.has(p.id));
  }

  function placeCard(place, extraClass = "") {
    const saved = state.saved.includes(place.id);
    const tier = tierOf(place.price);
    return `
      <article class="card ${extraClass}" data-href="#/place/${encodeURIComponent(place.id)}" tabindex="0" role="link">
        <div class="card-art">
          <span class="card-emoji" aria-hidden="true">${placeEmoji(place)}</span>
          ${showBadge(place) ? `<span class="card-badge pill pill-accent">${esc(loc(place.badge))}</span>` : ""}
          ${place.price > 0 ? `<span class="card-tier pill">${esc(tierLabel(tier))}</span>` : ""}
          <span class="card-price">${esc(priceText(place))}${place.price ? `<small>${esc(placeUnit(place))}</small>` : ""}</span>
          <button class="card-save ${saved ? "is-saved" : ""}" type="button" data-save="${esc(place.id)}" aria-pressed="${saved}" aria-label="${esc(saved ? t("card.saved") : t("card.save"))}">${saved ? icon("bookmarkFill") : icon("bookmark")}</button>
        </div>
        <div class="card-body">
          <div class="card-cat">${esc(categoryLabel(place.category))}</div>
          <h2>${esc(loc(place.name))}</h2>
          <p class="card-hook">${esc(loc(place.hook))}</p>
          <div class="card-meta">
            <span>${icon("pin")}${esc(loc(place.metro) || loc(place.district))}</span>
            ${place.rating ? `<span class="sep card-rating-sep">·</span><span class="card-rating">${icon("star")}${esc(place.rating.toFixed(1))}</span>` : ""}
            <span class="sep">·</span>
            <span class="card-people">${icon("users")}${esc(companyShort(place))}</span>
          </div>
        </div>
      </article>`;
  }

  function featureCard(place) {
    return `
      <a class="feature" href="#/place/${encodeURIComponent(place.id)}">
        <div class="feature-art">
          <span class="feature-emoji" aria-hidden="true">${placeEmoji(place)}</span>
          ${place.price > 0 ? `<span class="feature-tier pill">${esc(tierLabel(tierOf(place.price)))}</span>` : ""}
          <span class="feature-price"><b>${esc(priceText(place))}</b><span>${esc(placeUnit(place))}</span></span>
        </div>
        <div class="feature-body">
          <div class="feature-cat">${esc(categoryLabel(place.category))}</div>
          <h2>${esc(loc(place.name))}</h2>
          <p class="feature-hook">${esc(loc(place.hook))}</p>
          <div class="feature-foot">
            <span>${icon("pin")} ${esc(loc(place.metro) || loc(place.district))}</span>
            <span class="link-arrow">${esc(t("hero.open"))} ${icon("arrow")}</span>
          </div>
        </div>
      </a>`;
  }

  function signalCard(signal, wide = false) {
    const source = signal.publisher || loc(signal.sourceName);
    const price = signal.price === 0 ? t("price.free") : signal.price ? money(signal.price) : t("price.inSource");
    const unit = signal.price ? `<span>${esc(loc(signal.priceUnit) || "")}</span>` : "";
    const media = signal.image
      ? `<img src="${esc(signal.image)}" alt="" loading="lazy" referrerpolicy="no-referrer" onerror="this.style.display='none'">`
      : "";
    return `
      <a class="signal ${wide ? "wide" : ""}" href="#/idea/${encodeURIComponent(signal.id)}">
        <div class="signal-media"><span class="emoji" aria-hidden="true">${categoryEmoji(signal.category)}</span>${media}</div>
        <div class="signal-content">
          <div class="signal-top">
            <span class="signal-source">${esc(source)}</span>
            <span class="signal-dot"></span>
            <span class="signal-date">${esc(relative(signal.publishedAt))}</span>
          </div>
          <h3>${esc(loc(signal.title))}</h3>
          <p class="signal-summary">${esc(loc(signal.summary))}</p>
          <div class="signal-foot">
            <span class="signal-price">${esc(price)} ${unit}</span>
            <span class="signal-more">${icon("up")}</span>
          </div>
        </div>
      </a>`;
  }

  function saveButton(place, variant = "btn") {
    const saved = state.saved.includes(place.id);
    return `<button class="${variant} ${saved ? "is-saved" : ""}" type="button" data-save="${esc(place.id)}" aria-pressed="${saved}">${saved ? icon("bookmarkFill") : icon("bookmark")}<span>${esc(saved ? t("detail.saved") : t("detail.save"))}</span></button>`;
  }

  function renderHeader() {
    const section = currentSection();
    const savedCount = state.saved.length;
    const langLabel = state.lang === "ru" ? "EN" : "RU";
    headerEl.innerHTML = `
      <div class="header-inner">
        <a class="brand" href="#/">
          <span class="brand-word">стоит<span class="brand-dot">.</span></span>
          <span class="brand-sub">${esc(t("brand.sub"))}</span>
        </a>
        <nav class="nav" id="main-nav" aria-label="Основная навигация">
          <a href="#/" class="${section === "home" ? "active" : ""}">${esc(t("nav.home"))}</a>
          <a href="#/places" class="${section === "places" || section === "place" ? "active" : ""}">${esc(t("nav.places"))}</a>
          <a href="#/sources" class="${section === "sources" || section === "idea" ? "active" : ""}">${esc(t("nav.sources"))}</a>
          <a href="#/saved" class="${section === "saved" ? "active" : ""}">${esc(t("nav.saved"))}${savedCount ? `<span class="nav-count" data-saved-count>${savedCount}</span>` : ""}</a>
        </nav>
        <div class="header-actions">
          <span class="header-updated">${esc(updatedText())}</span>
          <button class="icon-btn lang-btn" type="button" data-action="lang" aria-label="${esc(t("header.lang"))}: ${langLabel}" title="${esc(t("header.lang"))}">${langLabel}</button>
          <button class="icon-btn" type="button" data-action="theme" aria-label="${esc(t("header.theme"))}" title="${esc(t("header.theme"))}">${state.theme === "dark" ? icon("sun") : icon("moon")}</button>
          <button class="icon-btn ${state.refreshing ? "spinning" : ""}" type="button" data-action="refresh" aria-label="${esc(t("header.refresh"))}" title="${esc(t("header.refresh"))}">${icon("refresh")}</button>
          <button class="icon-btn menu-btn" type="button" data-action="menu" aria-label="${esc(t("header.menu"))}" aria-expanded="false" aria-controls="main-nav">${icon("menu")}</button>
        </div>
      </div>`;
    const offline = document.getElementById("offline-banner");
    if (offline) headerEl.insertAdjacentElement("afterend", offline);
  }

  function renderFooter() {
    const sources = state.feed ? state.feed.sources : [];
    const note = state.feed && state.feed.note ? loc(state.feed.note) : t("footer.note");
    footerEl.innerHTML = `
      <div class="footer-inner">
        <div class="footer-brand">
          <span class="brand-word">стоит<span class="brand-dot">.</span></span>
          <p>${esc(t("footer.about"))}</p>
          <p class="footer-note">${esc(note)}</p>
        </div>
        <div class="footer-col">
          <h3>${esc(t("footer.nav"))}</h3>
          <a href="#/">${esc(t("nav.home"))}</a>
          <a href="#/places">${esc(t("nav.places"))}</a>
          <a href="#/sources">${esc(t("nav.sources"))}</a>
          <a href="#/saved">${esc(t("nav.saved"))}</a>
        </div>
        <div class="footer-col">
          <h3>${esc(t("footer.sources"))}</h3>
          <a href="#/sources">${esc(t("footer.allSources"))}</a>
          ${sources.slice(0, 3).map((s) => `<a href="${esc(s.homepage)}" target="_blank" rel="noopener noreferrer">${esc(loc(s.name))}</a>`).join("")}
        </div>
      </div>
      <div class="footer-bottom">
        <span>© ${new Date().getFullYear()} СТОИТ · ${esc(t("footer.rights"))} · <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noopener noreferrer">${esc(t("footer.osm"))}</a></span>
        <span class="mono">${esc(t("footer.updated"))}: ${esc(state.feed ? fmtDateTime(state.feed.updatedAt) : "—")} · Made by Deprice</span>
      </div>`;
  }

  function renderHome() {
    if (!state.feed) return renderError();
    const hero = dailyPicks(1)[0];
    const signals = homeSignals(5);
    const counts = tierCounts();
    const stats = state.feed.stats || {};
    const freeCount = counts.free;
    const sourceCount = stats.sourcesTotal || (state.feed.sources || []).length;
    const tierQuery = { free: "max=0", low: "max=300", mid: "max=700", high: "max=1500", premium: "min=1501" };
    const tierStrip = TIERS.map((tier) => `
      <a class="tier" href="#/places?${tierQuery[tier.id]}">
        <span class="tier-label"><b>${esc(tierLabel(tier.id))}</b><span>${esc(t("tier." + tier.id + ".sub"))}</span></span>
        <span class="tier-count">${counts[tier.id]}</span>
      </a>`).join("");

    view.innerHTML = `
      <section class="hero">
        <div class="hero-copy">
          <span class="kicker"><span class="dot"></span>${esc(t("hero.kicker", { n: sourceCount }))}</span>
          <h1>${t("hero.title")}</h1>
          <p class="hero-lead">${t("hero.lead", { n: sourceCount })}</p>
          <div class="hero-actions">
            <a class="btn btn-primary" href="#/places">${esc(t("hero.cta1"))} ${icon("arrow")}</a>
            <button class="btn" type="button" data-plan>${icon("spark")} ${esc(t("hero.cta2"))}</button>
          </div>
          <div class="hero-meta">
            <div class="metric"><strong>${stats.places || state.feed.places.length}</strong><span>${esc(t("hero.metric.places"))}</span></div>
            <div class="metric"><strong>${sourceCount}</strong><span>${esc(t("hero.metric.sources"))}</span></div>
            <div class="metric"><strong>${freeCount}</strong><span>${esc(t("hero.metric.free"))}</span></div>
          </div>
        </div>
        <div class="hero-stack">
          ${hero ? featureCard(hero) : ""}
        </div>
      </section>

      <div class="tiers">${tierStrip}</div>

      <section class="section">
        <div class="section-head">
          <div>
            <span class="kicker"><span class="dot"></span>${esc(t("home.fresh.kicker"))}</span>
            <h2 class="section-title">${esc(t("home.fresh.title"))}</h2>
            <p class="section-sub">${esc(t("home.fresh.sub"))}</p>
          </div>
          <a class="link-arrow" href="#/sources">${esc(t("nav.sources"))} ${icon("arrow")}</a>
        </div>
        ${signals.length
          ? `<div class="signal-grid">${signals.map((s, i) => signalCard(s, i === 0)).join("")}</div>`
          : `<div class="empty-state"><span class="emoji">🕯</span><h2>${esc(t("home.fresh.title"))}</h2><p>${esc(t("home.fresh.empty"))}</p></div>`}
      </section>

      <section class="section">
        <div class="section-head">
          <div>
            <span class="kicker"><span class="dot"></span>${esc(t("home.all.kicker"))}</span>
            <h2 class="section-title">${esc(t("home.all.title"))}</h2>
            <p class="section-sub">${esc(t("home.all.sub"))}</p>
          </div>
          <a class="link-arrow" href="#/places">${esc(t("home.all.cta"))} ${icon("arrow")}</a>
        </div>
        <div class="grid-3">${previewPlaces(6).map((p) => placeCard(p)).join("")}</div>
      </section>

      <div class="plan-banner">
        <div>
          <span class="kicker"><span class="dot"></span>${esc(t("home.plan.kicker"))}</span>
          <h2>${esc(t("home.plan.title"))}</h2>
          <p>${esc(t("home.plan.sub"))}</p>
        </div>
        <button class="btn btn-primary" type="button" data-plan>${icon("spark")} ${esc(t("home.plan.cta"))}</button>
      </div>`;
  }

  function filterButton(group, value, label, count, active) {
    return `<button class="filter-btn ${active ? "active" : ""}" type="button" data-filter="${group}" data-value="${esc(value)}" aria-pressed="${active}"><span>${esc(label)}</span>${count != null ? `<span class="n">${count}</span>` : ""}</button>`;
  }

  function budgetButton(label, min, max, active) {
    return `<button class="filter-btn ${active ? "active" : ""}" type="button" data-budget-min="${min}" data-budget-max="${max == null ? "" : max}" aria-pressed="${active}"><span>${esc(label)}</span></button>`;
  }

  function sortLabel(value) {
    if (value === "rating") return t("sort.rating");
    if (value === "name") return t("sort.name");
    return t("sort.price");
  }

  function parseList(value) {
    return String(value || "").split(",").map((x) => x.trim()).filter(Boolean);
  }

  function renderPlaces() {
    if (!state.feed) return renderError();
    state.visibleCount = 12;
    const params = parseRoute().params;
    state.filters.cats = params.has("cat") ? parseList(params.get("cat")) : [];
    state.filters.moods = params.has("mood") ? parseList(params.get("mood")) : [];
    state.filters.q = params.get("q") || "";
    state.filters.maxPrice = params.has("max") ? (params.get("max") === "" ? null : Number(params.get("max"))) : null;
    state.filters.minPrice = params.has("min") ? (Number(params.get("min")) || 0) : 0;

    const catCounts = facetCategoryCounts();
    const moodCounts = facetMoodCounts();
    const allTags = tagPairs();
    const activeCount = [state.filters.cats.length > 0, state.filters.moods.length > 0, state.filters.maxPrice != null || state.filters.minPrice > 0, !!state.filters.q].filter(Boolean).length;
    const budgetActive = state.filters.maxPrice == null && state.filters.minPrice === 0;

    const budgetButtons = [
      budgetButton(t("filters.all"), 0, null, budgetActive),
      budgetButton(t("tier.free"), 0, 0, state.filters.minPrice === 0 && state.filters.maxPrice === 0),
      budgetButton(t("tier.low"), 1, 300, state.filters.minPrice === 1 && state.filters.maxPrice === 300),
      budgetButton(t("tier.mid"), 301, 700, state.filters.minPrice === 301 && state.filters.maxPrice === 700),
      budgetButton(t("tier.high"), 701, 1500, state.filters.minPrice === 701 && state.filters.maxPrice === 1500),
      budgetButton("1500+ ₽", 1501, null, state.filters.minPrice === 1501 && state.filters.maxPrice == null),
    ].join("");

    const allCategories = Array.from(new Set(state.feed.places.map((p) => p.category)));
    const catButtons = [
      filterButton("cat", "all", t("filters.all"), catCounts.all || 0, state.filters.cats.length === 0),
      ...allCategories.sort((a, b) => (catCounts[b] || 0) - (catCounts[a] || 0)).map((cat) => filterButton("cat", cat, categoryLabel(cat), catCounts[cat] || 0, state.filters.cats.includes(cat))),
    ].join("");
    const moodOptions = allTags
      .map((tag) => ({ ...tag, count: moodCounts[tag.ru] || 0 }))
      .sort((a, b) => b.count - a.count);
    const shownMoods = moodOptions.filter((tag, index) => index < 12 || state.filters.moods.includes(tag.ru));
    const moodButtons = [
      filterButton("mood", "all", t("filters.all"), moodCounts.all || 0, state.filters.moods.length === 0),
      ...shownMoods.map((tag) => filterButton("mood", tag.ru, state.lang === "ru" ? tag.ru : tag.en, tag.count, state.filters.moods.includes(tag.ru))),
    ].join("");

    view.innerHTML = `
      <div class="page-head">
        <span class="kicker"><span class="dot"></span>${esc(t("places.kicker"))}</span>
        <h1>${esc(t("places.title"))}</h1>
        <p>${esc(t("places.sub"))}</p>
      </div>
      <div class="catalog">
        <details class="filters" ${window.matchMedia("(max-width: 860px)").matches ? "" : "open"}>
          <summary>${esc(t("filters.title"))}${activeCount ? ` · ${activeCount}` : ""} ${icon("menu")}</summary>
          <div class="filters-body">
            <div class="filter-group">
              <div class="filter-title">${esc(t("filters.budget"))}</div>
              <div class="filter-list">${budgetButtons}</div>
              <div class="budget-custom">
                <label for="budget-max">${esc(t("filters.customBudget"))}</label>
                <div class="budget-input-wrap">
                  <input type="number" id="budget-max" min="0" step="50" inputmode="numeric" placeholder="500" value="${state.filters.maxPrice != null ? state.filters.maxPrice : ""}">
                  <span>₽ ${esc(t("filters.perPerson"))}</span>
                </div>
              </div>
            </div>
            <div class="filter-group">
              <div class="filter-title">${esc(t("filters.category"))} · ${esc(t("filters.multi"))}</div>
              <div class="filter-list">${catButtons}</div>
            </div>
            <div class="filter-group">
              <div class="filter-title">${esc(t("filters.mood"))} · ${esc(t("filters.multi"))}</div>
              <div class="filter-list">${moodButtons}</div>
            </div>
            <button class="reset-btn" type="button" data-filter-reset>${esc(t("filters.reset"))}</button>
          </div>
        </details>
        <div class="catalog-main">
          <div class="toolbar">
            <label class="search-box">
              <span class="sr-only">${esc(t("search.placeholder"))}</span>
              ${icon("search")}
              <input type="search" id="search-input" value="${esc(state.filters.q)}" placeholder="${esc(t("search.placeholder"))}" autocomplete="off">
            </label>
            <div class="sort-wrap" data-sort-wrap>
              <button class="sort-control" type="button" data-sort-toggle aria-haspopup="listbox" aria-expanded="false">
                <span>${esc(sortLabel(state.filters.sort))}</span>
                ${icon("chevron")}
              </button>
              <div class="sort-menu" role="listbox" aria-label="${esc(t("sort.label"))}">
                ${["price", "rating", "name"].map((value) => `<button class="sort-option ${state.filters.sort === value ? "active" : ""}" type="button" role="option" aria-selected="${state.filters.sort === value}" data-sort-option="${value}">${esc(sortLabel(value))}</button>`).join("")}
              </div>
            </div>
          </div>
          <div id="catalog-results"></div>
        </div>
      </div>`;
    renderCatalogResults();
  }

  function renderCatalogResults() {
    const container = $("#catalog-results");
    if (!container) return;
    const list = filteredPlaces();
    const shown = list.slice(0, state.visibleCount);
    container.innerHTML = `
      <div class="results-line">
        <span>${esc(t("results.count", { n: list.length }))} · ${esc(t("results.of", { n: state.feed.places.length }))}</span>
        <span>${esc(t("places.kicker"))}</span>
      </div>
      ${list.length
        ? `<div class="grid-3">${shown.map((p) => placeCard(p)).join("")}</div>
           ${list.length > shown.length ? `<div class="load-more"><button class="btn" type="button" data-load-more>${esc(t("results.more"))} · ${list.length - shown.length}</button></div>` : ""}`
        : `<div class="empty-state"><span class="emoji">🔎</span><h2>${esc(t("results.noneTitle"))}</h2><p>${esc(t("results.noneText"))}</p><button class="btn" type="button" data-filter-reset>${esc(t("results.reset"))}</button></div>`}`;
  }

  function renderSources() {
    if (!state.feed) return renderError();
    const sources = state.feed.sources || [];
    const stats = state.feed.stats || {};
    const active = sources.filter((s) => s.status === "ok" || s.status === "cached").length;
    const sourceCard = (source) => {
      const status = source.status || "error";
      return `
        <article class="source-card">
          <div class="source-top">
            <span class="status-dot ${status === "ok" ? "" : status}"></span>
            <span class="source-kind">${esc(t("kind." + (source.kind || "media")))}</span>
            <span class="source-status">${esc(t("sources.status." + status))}</span>
          </div>
          <h3>${esc(loc(source.name))}</h3>
          <p>${esc(loc(source.description))}</p>
          <div class="source-foot">
            <span>${source.items ? esc(t("sources.items", { n: source.items })) : esc(t("sources.empty"))} · ${esc(relative(source.lastSync))}</span>
            <a href="${esc(source.homepage)}" target="_blank" rel="noopener noreferrer">${esc(t("sources.visit"))} ${icon("up")}</a>
          </div>
        </article>`;
    };
    const groupOrder = ["community", "telegram", "social", "media", "official", "catalog", "aggregator"];
    const groups = groupOrder
      .map((kind) => ({ kind, list: sources.filter((source) => (source.kind || "media") === kind) }))
      .filter((group) => group.list.length);
    const groupsHtml = groups.map((group) => `
      <div class="source-group">
        <div class="section-head">
          <div><h2 class="section-title">${esc(t("sourceGroup." + group.kind))}</h2></div>
          <span class="tier-count">${group.list.length}</span>
        </div>
        <div class="source-grid">${group.list.map(sourceCard).join("")}</div>
      </div>`).join("");

    view.innerHTML = `
      <div class="page-head">
        <span class="kicker"><span class="dot"></span>${esc(t("sources.kicker"))}</span>
        <h1>${esc(t("sources.title"))}</h1>
        <p>${esc(t("sources.sub"))}</p>
      </div>
      <section class="section" style="padding-top:8px">
        <div class="status-strip">
          <span>${esc(t("sources.updated"))}: <b>${esc(fmtDateTime(state.feed.updatedAt))}</b></span>
          <span class="sep"></span>
          <span>${esc(t("sources.next"))}: <b>${esc(fmtDateTime(state.feed.nextUpdate))}</b></span>
          <span class="sep"></span>
          <span>${esc(t("sources.active"))}: <b>${active}/${sources.length}</b></span>
          <span class="sep"></span>
          <span>${esc(t("sources.materials"))}: <b>${stats.signals || state.feed.signals.length}</b></span>
          <button class="btn btn-sm" type="button" data-action="refresh" ${state.refreshing ? "disabled" : ""}>${state.refreshing ? icon("refresh") + " " + esc(t("sources.refreshing")) : icon("refresh") + " " + esc(t("sources.refresh"))}</button>
        </div>
        <div class="source-groups">${groupsHtml}</div>
        <div class="section-head" style="margin-top:52px">
          <div><h2 class="section-title">${esc(t("sources.howTitle"))}</h2></div>
        </div>
        <div class="how-grid">
          <div class="how-card"><span class="how-num">01</span><h3>${esc(t("sources.how1.title"))}</h3><p>${esc(t("sources.how1.text"))}</p></div>
          <div class="how-card"><span class="how-num">02</span><h3>${esc(t("sources.how2.title"))}</h3><p>${esc(t("sources.how2.text"))}</p></div>
          <div class="how-card"><span class="how-num">03</span><h3>${esc(t("sources.how3.title"))}</h3><p>${esc(t("sources.how3.text"))}</p></div>
        </div>
        <p class="muted" style="margin-top:22px;font-size:11.5px">${esc(t("sources.note"))}</p>
      </section>`;
  }

  function renderSaved() {
    if (!state.feed) return renderError();
    const places = savedPlaces();
    view.innerHTML = `
      <div class="page-head">
        <span class="kicker"><span class="dot"></span>${esc(t("saved.kicker"))}</span>
        <h1>${esc(t("saved.title"))}</h1>
        <p>${esc(t("saved.sub"))}</p>
      </div>
      ${places.length
        ? `<section class="section" style="padding-top:10px">
            <div class="results-line"><span>${esc(t("saved.count", { n: places.length }))}</span><button class="btn btn-sm" type="button" data-plan>${icon("spark")} ${esc(t("saved.plan"))}</button></div>
            <div class="grid-3">${places.map((p) => placeCard(p)).join("")}</div>
          </section>`
        : `<div class="saved-empty"><div class="big">🔖</div><h2>${esc(t("saved.emptyTitle"))}</h2><p>${esc(t("saved.emptyText"))}</p><a class="btn btn-primary" href="#/places">${esc(t("saved.cta"))} ${icon("arrow")}</a></div>`}`;
  }

  function renderPlace(id) {
    if (!state.feed) return renderError();
    const place = state.feed.places.find((p) => p.id === id);
    if (!place) return renderNotFound();
    const tier = tierOf(place.price);
    const tags = (place.tags && (place.tags[state.lang] || place.tags.ru)) || [];
    const similar = state.feed.places
      .filter((p) => p.id !== place.id && p.category === place.category)
      .slice(0, 3);
    const mapUrl = "https://yandex.ru/maps/?text=" + encodeURIComponent(place.mapQuery || (loc(place.name) + " Москва"));
    const deal = place.deal;
    const days = ["0", "1", "2", "3", "4", "5", "6"];

    view.innerHTML = `
      <article class="place-page">
        <div class="breadcrumbs">
          <a href="#/places">${esc(t("nav.places"))}</a> ${icon("arrow")}
          <span>${esc(categoryLabel(place.category))}</span>
        </div>
        <div class="place-hero">
          <div class="place-art">
            <span class="place-emoji" aria-hidden="true">${placeEmoji(place)}</span>
            <div class="art-top">
              <span class="pill">${esc(tierLabel(tier))}</span>
              ${showBadge(place) ? `<span class="pill pill-accent">${esc(loc(place.badge))}</span>` : ""}
            </div>
            <div class="art-bottom">${esc(loc(place.source && place.source.name) || "СТОИТ")} · ${esc(categoryLabel(place.category))}</div>
          </div>
          <div class="place-info">
            <span class="kicker"><span class="dot"></span>${esc(categoryLabel(place.category))} · ${esc(tierLabel(tier))}</span>
            <h1>${esc(loc(place.name))}</h1>
            <p class="place-hook">${esc(loc(place.hook))}</p>
            <div class="place-price">
              <strong>${esc(priceText(place))}</strong>
              <span>${esc(placeUnit(place))}</span>
              ${place.priceApprox ? `<span class="pill pill-accent approx-pill">${esc(t("detail.approx"))}</span>` : ""}
            </div>
            <p class="price-note">${esc(loc(place.priceNote))}</p>
            <div class="place-actions">
              <a class="btn btn-primary" href="${esc(mapUrl)}" target="_blank" rel="noopener noreferrer">${icon("map")} ${esc(t("detail.map"))}</a>
              ${saveButton(place)}
              <button class="btn" type="button" data-share="${esc(place.id)}">${icon("share")} ${esc(t("detail.share"))}</button>
            </div>
            <div class="meta-grid">
              <div class="meta-item">${icon("metro")}<div><small>${esc(t("detail.metro"))}</small><b>${esc(loc(place.metro))}</b></div></div>
              <div class="meta-item">${icon("pin")}<div><small>${esc(t("detail.address"))}</small><b>${esc(loc(place.address))}</b></div></div>
              <div class="meta-item">${icon("clock")}<div><small>${esc(t("detail.hours"))}</small><b>${esc(loc(place.hours))}</b></div></div>
              <div class="meta-item">${icon("users")}<div><small>${esc(t("detail.company"))}</small><b>${esc(loc(place.company))}</b></div></div>
              <div class="meta-item">${icon("star")}<div><small>${esc(t("detail.rating"))}</small><b>${esc(place.rating ? place.rating.toFixed(1) : "—")}</b></div></div>
              <div class="meta-item">${icon("pin")}<div><small>${esc(t("detail.district"))}</small><b>${esc(loc(place.district))}</b></div></div>
            </div>
            <div class="tag-row">${tags.map((tag) => `<span class="pill">${esc(tag)}</span>`).join("")}</div>
          </div>
        </div>

        <div class="place-body">
          <div class="prose">
            <h2>${esc(t("detail.about"))}</h2>
            <p class="lead">${esc(loc(place.about))}</p>
            <h2 style="margin-top:34px">${esc(t("detail.get"))}</h2>
            <ul class="bullets">${((place.whatYouGet && (place.whatYouGet[state.lang] || place.whatYouGet.ru)) || []).map((item) => `<li>${esc(item)}</li>`).join("")}</ul>
            <p class="faint" style="margin-top:30px;font-size:11px">${esc(t("detail.note"))}</p>
          </div>
          <aside>
            <div class="side-card">
              <span class="pill">${icon("users")} ${esc(t("detail.withWhom"))}</span>
              <h3>${esc(loc(place.company))}</h3>
              <p>${esc(tags.slice(0, 5).join(" · "))}</p>
            </div>
            <div class="side-card accent">
              <span class="pill pill-accent">${icon("spark")} ${esc(t("detail.tip"))}</span>
              <p>${esc(loc(place.tip))}</p>
            </div>
            ${deal ? `<div class="side-card">
              <span class="pill">${esc(t("detail.deal"))}</span>
              <h3>${esc(loc(deal.title))}</h3>
              <p>${esc(loc(deal.detail))}</p>
              <div class="deal-days">${days.map((d) => `<span class="day-dot ${deal.days && deal.days.includes(Number(d)) ? "on" : ""}">${esc(t("day." + d))}</span>`).join("")}</div>
            </div>` : ""}
            <div class="side-card">
              <span class="pill">${esc(t("detail.priceFor"))}</span>
              <h3>${esc(priceText(place))} · ${esc(placeUnit(place))}</h3>
              <p>${esc(loc(place.priceNote))}</p>
            </div>
            <div class="side-card">
              <span class="pill">${esc(t("detail.source"))}</span>
              <h3>${esc(loc(place.source && place.source.name) || "СТОИТ")}</h3>
              <p>${esc(updatedText())}</p>
            </div>
          </aside>
        </div>

        ${similar.length ? `<section class="similar">
          <div class="section-head"><div><h2 class="section-title">${esc(t("detail.similar"))}</h2></div><a class="link-arrow" href="#/places?cat=${encodeURIComponent(place.category)}">${esc(t("nav.places"))} ${icon("arrow")}</a></div>
          <div class="grid-3">${similar.map((p) => placeCard(p)).join("")}</div>
        </section>` : ""}
      </article>`;
  }

  function renderIdea(id) {
    if (!state.feed) return renderError();
    const signal = state.feed.signals.find((s) => s.id === id);
    if (!signal) return renderNotFound();
    const source = state.feed.sources.find((s) => s.id === signal.sourceId);
    const related = state.feed.places.filter((p) => p.category === signal.category).slice(0, 3);
    const price = signal.price === 0 ? t("price.free") : signal.price ? money(signal.price) : t("idea.noPrice");
    view.innerHTML = `
      <article class="place-page" style="max-width:960px">
        <div class="breadcrumbs"><a href="#/sources">${esc(t("nav.sources"))}</a> ${icon("arrow")} ${esc(t("idea.kicker"))}</div>
        <div class="place-hero" style="grid-template-columns:minmax(0,.85fr) minmax(0,1.15fr)">
          <div class="place-art" style="min-height:340px">
            ${signal.image ? `<img src="${esc(signal.image)}" alt="" style="position:absolute;inset:0;width:100%;height:100%;object-fit:cover" referrerpolicy="no-referrer" onerror="this.remove()">` : `<span class="place-emoji" aria-hidden="true">${categoryEmoji(signal.category)}</span>`}
            <div class="art-top"><span class="pill">${esc(relative(signal.publishedAt))}</span>${signal.machineTranslated ? `<span class="pill">${esc(t("idea.translated"))}</span>` : ""}</div>
          </div>
          <div class="place-info">
            <span class="kicker"><span class="dot"></span>${esc(signal.publisher || loc(signal.sourceName))}</span>
            <h1 style="font-size:clamp(32px,4vw,48px)">${esc(loc(signal.title))}</h1>
            <p class="place-hook">${esc(loc(signal.summary))}</p>
            <div class="place-price"><strong>${esc(price)}</strong>${signal.price ? `<span>${esc(loc(signal.priceUnit) || "")}</span>` : ""}</div>
            <p class="price-note">${esc(t("idea.published"))}: ${esc(fmtDateTime(signal.publishedAt))}</p>
            <div class="place-actions">
              <a class="btn btn-primary" href="${esc(signal.url)}" target="_blank" rel="noopener noreferrer">${icon("up")} ${esc(t("idea.original"))}</a>
              ${source ? `<a class="btn" href="${esc(source.homepage)}" target="_blank" rel="noopener noreferrer">${icon("rss")} ${esc(loc(source.name))}</a>` : ""}
            </div>
          </div>
        </div>
        ${related.length ? `<section class="similar">
          <div class="section-head"><div><h2 class="section-title">${esc(t("idea.related"))}</h2></div><a class="link-arrow" href="#/places?cat=${encodeURIComponent(signal.category)}">${esc(t("nav.places"))} ${icon("arrow")}</a></div>
          <div class="grid-3">${related.map((p) => placeCard(p)).join("")}</div>
        </section>` : ""}
      </article>`;
  }

  function renderNotFound() {
    view.innerHTML = `
      <div class="empty-state" style="max-width:720px;margin:70px auto;border-style:solid">
        <span class="emoji">🧭</span>
        <h2>404</h2>
        <p>${esc(t("results.noneText"))}</p>
        <a class="btn" href="#/">${esc(t("nav.home"))} ${icon("arrow")}</a>
      </div>`;
  }

  function renderError() {
    view.innerHTML = `
      <div class="empty-state" style="max-width:720px;margin:70px auto;border-style:solid">
        <span class="emoji">📡</span>
        <h2>${esc(t("error.title"))}</h2>
        <p>${esc(t("error.text"))}</p>
        <button class="btn btn-primary" type="button" data-action="retry">${icon("refresh")} ${esc(t("error.retry"))}</button>
      </div>`;
  }

  function updateMeta() {
    const route = parseRoute();
    const section = route.parts[0] || "home";
    let title = t("meta.home");
    if (section === "places") title = t("places.title") + " — СТОИТ";
    else if (section === "sources") title = t("sources.title") + " — СТОИТ";
    else if (section === "saved") title = t("saved.title") + " — СТОИТ";
    else if (section === "place" && state.feed) {
      const p = state.feed.places.find((x) => x.id === route.parts[1]);
      if (p) title = loc(p.name) + " — СТОИТ";
    } else if (section === "idea" && state.feed) {
      const s = state.feed.signals.find((x) => x.id === route.parts[1]);
      if (s) title = loc(s.title) + " — СТОИТ";
    }
    document.title = title;
  }

  function renderRoute(scroll = true) {
    if (!state.feed) return;
    const route = parseRoute();
    const section = route.parts[0] || "home";
    document.body.classList.remove("modal-open");
    $$(".nav.open").forEach((nav) => nav.classList.remove("open"));
    const menu = $('[data-action="menu"]');
    if (menu) menu.setAttribute("aria-expanded", "false");
    updateMeta();
    renderHeader();
    renderFooter();
    if (section === "home") renderHome();
    else if (section === "places") renderPlaces();
    else if (section === "sources") renderSources();
    else if (section === "saved") renderSaved();
    else if (section === "place") renderPlace(route.parts[1]);
    else if (section === "idea") renderIdea(route.parts[1]);
    else renderNotFound();
    if (scroll) window.scrollTo({ top: 0, behavior: "auto" });
  }

  function hideSplash() {
    const splash = document.getElementById("splash");
    if (!splash) return;
    const elapsed = Date.now() - (state.bootAt || Date.now());
    const wait = Math.max(0, 650 - elapsed);
    setTimeout(() => {
      splash.classList.add("done");
      setTimeout(() => splash.remove(), 500);
    }, wait);
  }

  function showToast(message) {
    if (!toastEl) return;
    toastEl.textContent = message;
    toastEl.classList.add("show");
    clearTimeout(state.toastTimer);
    state.toastTimer = setTimeout(() => toastEl.classList.remove("show"), 2800);
  }

  function syncFiltersToUrl() {
    const params = new URLSearchParams();
    if (state.filters.cats.length) params.set("cat", state.filters.cats.join(","));
    if (state.filters.moods.length) params.set("mood", state.filters.moods.join(","));
    if (state.filters.maxPrice != null) params.set("max", String(state.filters.maxPrice));
    if (state.filters.minPrice > 0) params.set("min", String(state.filters.minPrice));
    if (state.filters.q.trim()) params.set("q", state.filters.q.trim());
    const qs = params.toString();
    const next = "#/places" + (qs ? "?" + qs : "");
    if (location.hash !== next) history.replaceState(null, "", next);
  }

  function toggleSave(id) {
    const index = state.saved.indexOf(id);
    if (index >= 0) state.saved.splice(index, 1);
    else state.saved.push(id);
    try { localStorage.setItem(SAVED_KEY, JSON.stringify(state.saved)); } catch (_) {}
    $$("[data-save]").forEach((btn) => {
      if (btn.getAttribute("data-save") !== id) return;
      const saved = state.saved.includes(id);
      btn.classList.toggle("is-saved", saved);
      btn.setAttribute("aria-pressed", saved);
      if (btn.classList.contains("card-save")) {
        btn.innerHTML = saved ? icon("bookmarkFill") : icon("bookmark");
        btn.setAttribute("aria-label", saved ? t("card.saved") : t("card.save"));
      } else {
        btn.innerHTML = `${saved ? icon("bookmarkFill") : icon("bookmark")}<span>${esc(saved ? t("detail.saved") : t("detail.save"))}</span>`;
      }
    });
    const navCount = $("[data-saved-count]");
    if (navCount) navCount.textContent = state.saved.length;
    showToast(index >= 0 ? t("toast.removed") : t("toast.saved"));
    if (currentSection() === "saved") renderRoute(false);
  }

  async function copyText(text) {
    try {
      await navigator.clipboard.writeText(text);
      showToast(t("toast.copied"));
    } catch (_) {
      const ta = document.createElement("textarea");
      ta.value = text;
      document.body.appendChild(ta);
      ta.select();
      try { document.execCommand("copy"); showToast(t("toast.copied")); } catch (__) {}
      ta.remove();
    }
  }

  function sharePlace(id) {
    const place = state.feed && state.feed.places.find((p) => p.id === id);
    if (!place) return;
    const url = location.origin + location.pathname + "#/place/" + encodeURIComponent(id);
    const data = { title: loc(place.name), text: loc(place.hook), url };
    if (navigator.share) navigator.share(data).catch(() => {});
    else copyText(url);
  }

  function setTheme(theme) {
    state.theme = theme;
    document.documentElement.dataset.theme = theme;
    try { localStorage.setItem(THEME_KEY, theme); } catch (_) {}
    const meta = document.querySelector('meta[name="theme-color"]');
    if (meta) meta.setAttribute("content", theme === "dark" ? "#09090c" : "#f5f4f8");
    renderHeader();
  }

  function applyStaticI18n() {
    $$("[data-i18n]").forEach((el) => {
      const key = el.getAttribute("data-i18n");
      if (key) el.textContent = t(key);
    });
    document.documentElement.lang = state.lang;
  }

  function setLang(lang) {
    state.lang = lang;
    try { localStorage.setItem(LANG_KEY, lang); } catch (_) {}
    applyStaticI18n();
    renderRoute(false);
    if (modalRoot.children.length) {
      if (state.plan) renderPlanModal();
      else closeModal();
    }
  }

  function openModal(html) {
    modalRoot.innerHTML = `<div class="modal-backdrop" data-close-modal>${html}</div>`;
    document.body.classList.add("modal-open");
    const close = $(".modal-close");
    if (close) close.focus();
  }

  function closeModal() {
    modalRoot.innerHTML = "";
    document.body.classList.remove("modal-open");
  }

  function planStepCard(step, index) {
    return `
      <div class="plan-step">
        <span class="plan-num">${index + 1}</span>
        <div>
          <h3><a href="#/place/${encodeURIComponent(step.id)}">${esc(loc(step.name))}</a></h3>
          <p>${esc(categoryLabel(step.category))} · ${esc(loc(step.metro) || loc(step.district))} · ${esc(companyShort(step))}</p>
        </div>
        <div class="price">${esc(priceText(step))}<small>${esc(placeUnit(step))}</small></div>
      </div>`;
  }

  function renderPlanModal() {
    if (!state.plan) state.plan = { budget: 1000, attempt: 0, party: "any", nonce: 0 };
    const { budget, attempt, party = "any", nonce = 0 } = state.plan;
    const plan = buildPlan(budget, attempt, party, nonce);
    if (plan && plan.steps.length) rememberPlan(plan.steps);
    const total = plan ? plan.total : 0;
    const within = budget === 0 || total <= budget;
    const budgets = [
      { value: 500, label: "500 ₽" },
      { value: 1000, label: "1 000 ₽" },
      { value: 2000, label: "2 000 ₽" },
      { value: 0, label: t("plan.any") },
    ];
    const parties = ["any", "friends", "date", "solo", "family"];
    openModal(`
      <div class="modal" role="dialog" aria-modal="true" aria-labelledby="plan-title">
        <div class="modal-head">
          <div>
            <span class="kicker"><span class="dot"></span>${esc(t("plan.kicker"))}</span>
            <h2 id="plan-title">${esc(t("plan.title"))}</h2>
            <p>${esc(t("plan.sub"))}</p>
          </div>
          <button class="icon-btn modal-close" type="button" data-close-modal aria-label="${esc(t("common.close"))}">${icon("close")}</button>
        </div>
        <div class="filter-title" style="margin-top:18px">${esc(t("plan.budget"))}</div>
        <div class="plan-budget" role="group" aria-label="${esc(t("plan.budget"))}">
          ${budgets.map((b) => `<button class="chip ${budget === b.value ? "active" : ""}" type="button" data-plan-budget="${b.value}">${esc(b.label)}</button>`).join("")}
        </div>
        <div class="budget-custom modal-budget">
          <label for="plan-custom-budget">${esc(t("plan.custom"))} · ${esc(t("plan.perPerson"))}</label>
          <div class="budget-input-wrap">
            <input type="number" id="plan-custom-budget" min="0" step="100" inputmode="numeric" placeholder="750" value="${budget > 0 ? budget : ""}">
            <span>₽</span>
          </div>
        </div>
        <div class="filter-title" style="margin-top:14px">${esc(t("plan.party"))}</div>
        <div class="plan-budget" role="group" aria-label="${esc(t("plan.party"))}">
          ${parties.map((p) => `<button class="chip ${party === p ? "active" : ""}" type="button" data-plan-party="${p}">${esc(t("party." + p))}</button>`).join("")}
        </div>
        ${plan && plan.steps.length
          ? `<div class="plan-list">${plan.steps.map(planStepCard).join("")}</div>
             <div class="plan-total"><span>${esc(t("plan.total"))} · ${esc(t("plan.perPerson"))} · ${esc(within ? t("plan.within") : t("plan.over"))}</span><strong>${esc(money(total))}</strong></div>`
          : `<p class="muted" style="padding:22px 0">${esc(t("plan.empty"))}</p>`}
        <div class="plan-actions">
          <button class="btn" type="button" data-plan-again>${icon("refresh")} ${esc(t("plan.again"))}</button>
          <button class="btn btn-primary" type="button" data-close-modal>${esc(t("plan.close"))}</button>
        </div>
      </div>`);
  }

  function openPlan(budget = 1000) {
    state.plan = { budget, attempt: 0, party: "any", nonce: 0 };
    renderPlanModal();
  }

  async function loadFeed(force = false, silent = false) {
    try {
      const res = await fetch("data/feed.json" + (force ? "?t=" + Date.now() : ""), { cache: "no-store" });
      if (!res.ok) throw new Error("HTTP " + res.status);
      const feed = await res.json();
      if (!feed || !Array.isArray(feed.places)) throw new Error("Bad feed");
      const changed = !state.feed || state.feed.updatedAt !== feed.updatedAt;
      state.feed = feed;
      state.offline = false;
      setOffline(false);
      try { localStorage.setItem(CACHE_KEY, JSON.stringify(feed)); } catch (_) {}
      if (silent && !changed) return;
      renderRoute(false);
      hideSplash();
    } catch (err) {
      if (!state.feed) {
        try {
          const cached = localStorage.getItem(CACHE_KEY);
          if (cached) {
            state.feed = JSON.parse(cached);
            state.offline = true;
            setOffline(true);
            renderRoute(false);
            hideSplash();
            return;
          }
        } catch (_) {}
        state.loadingError = true;
        renderError();
        hideSplash();
      } else if (!silent) {
        showToast(t("toast.error"));
      }
    }
  }

  async function checkServer() {
    try {
      const res = await fetch("/api/status", { cache: "no-store" });
      if (res.ok) {
        state.server = true;
        return await res.json();
      }
    } catch (_) {}
    state.server = false;
    return null;
  }

  function cloudRefreshApi() {
    const value = window.STOIT_CONFIG && window.STOIT_CONFIG.refreshApi;
    return String(value || "").replace(/\/+$/, "");
  }

  async function refreshData() {
    if (state.refreshing) return;
    const api = cloudRefreshApi();
    const cooldown = 20 * 60 * 1000;
    const last = Number(localStorage.getItem("stoit.lastRefresh") || 0);
    if (api && Date.now() - last < cooldown) {
      const minutes = Math.ceil((cooldown - (Date.now() - last)) / 60000);
      showToast(t("toast.cooldown", { min: minutes }));
      return;
    }
    state.refreshing = true;
    renderHeader();
    try {
      if (api) {
        const response = await fetch(`${api}/refresh`, { method: "POST" });
        if (response.status === 429) {
          let retry = 1200;
          try {
            const data = await response.json();
            if (data && data.retryAfter) retry = Number(data.retryAfter);
          } catch (_) {}
          localStorage.setItem("stoit.lastRefresh", String(Date.now()));
          showToast(t("toast.cooldown", { min: Math.ceil(retry / 60) }));
          return;
        }
        if (!response.ok) throw new Error("refresh dispatch failed");
        const before = state.feed ? state.feed.updatedAt : null;
        localStorage.setItem("stoit.lastRefresh", String(Date.now()));
        showToast(t("toast.refreshStarted"));
        let changed = false;
        for (let i = 0; i < 72; i += 1) {
          await new Promise((resolve) => setTimeout(resolve, 5000));
          await loadFeed(true, true);
          if (state.feed && state.feed.updatedAt !== before) {
            changed = true;
            break;
          }
        }
        showToast(changed ? t("toast.refreshed") : t("toast.refreshTimeout"));
      } else if ((location.hostname === "localhost" || location.hostname === "127.0.0.1") && await checkServer()) {
        await fetch("/api/refresh", { method: "POST" });
        for (let i = 0; i < 90; i += 1) {
          await new Promise((resolve) => setTimeout(resolve, 1400));
          const next = await checkServer();
          if (next && !next.refreshing) break;
        }
        await loadFeed(true);
        showToast(t("toast.refreshed"));
      } else {
        await loadFeed(true);
        showToast(t("toast.static"));
      }
    } catch (_) {
      showToast(t("toast.error"));
    } finally {
      state.refreshing = false;
      renderHeader();
      renderRoute(false);
    }
  }

  function setOffline(on) {
    let banner = document.getElementById("offline-banner");
    if (on && !banner) {
      banner = document.createElement("div");
      banner.id = "offline-banner";
      banner.className = "offline-banner";
      banner.innerHTML = icon("offline") + " " + esc(t("offline.text"));
      headerEl.insertAdjacentElement("afterend", banner);
    } else if (!on && banner) {
      banner.remove();
    }
  }

  function bindEvents() {
    document.addEventListener("click", (event) => {
      const target = event.target;
      if (!target.closest("[data-sort-wrap]")) {
        $$(".sort-wrap.open").forEach((el) => {
          el.classList.remove("open");
          const btn = el.querySelector("[data-sort-toggle]");
          if (btn) btn.setAttribute("aria-expanded", "false");
        });
      }
      const action = target.closest("[data-action]");
      if (action) {
        const name = action.getAttribute("data-action");
        if (name === "lang") setLang(state.lang === "ru" ? "en" : "ru");
        else if (name === "theme") setTheme(state.theme === "dark" ? "light" : "dark");
        else if (name === "refresh" || name === "retry") refreshData();
        else if (name === "menu") {
          const nav = $("#main-nav");
          if (nav) {
            const open = nav.classList.toggle("open");
            action.setAttribute("aria-expanded", open);
          }
        }
        return;
      }

      const save = target.closest("[data-save]");
      if (save) {
        event.preventDefault();
        event.stopPropagation();
        toggleSave(save.getAttribute("data-save"));
        return;
      }

      if (target.closest("[data-plan]")) {
        openPlan(1000);
        return;
      }
      const closer = target.closest("[data-close-modal]");
      if (closer) {
        if (closer.classList.contains("modal-backdrop")) {
          if (target === closer) {
            closeModal();
            return;
          }
        } else {
          closeModal();
          return;
        }
      }
      const planBudget = target.closest("[data-plan-budget]");
      if (planBudget) {
        state.plan = {
          budget: Number(planBudget.getAttribute("data-plan-budget")),
          attempt: 0,
          party: state.plan ? state.plan.party : "any",
          nonce: (state.plan ? state.plan.nonce : 0) + 1,
        };
        renderPlanModal();
        return;
      }
      const planParty = target.closest("[data-plan-party]");
      if (planParty) {
        state.plan = {
          budget: state.plan ? state.plan.budget : 1000,
          attempt: 0,
          party: planParty.getAttribute("data-plan-party"),
          nonce: (state.plan ? state.plan.nonce : 0) + 1,
        };
        renderPlanModal();
        return;
      }
      if (target.closest("[data-plan-again]")) {
        state.plan.attempt += 1;
        state.plan.nonce += 1;
        renderPlanModal();
        return;
      }

      const sortToggle = target.closest("[data-sort-toggle]");
      if (sortToggle) {
        const wrap = sortToggle.closest("[data-sort-wrap]");
        const open = wrap.classList.toggle("open");
        sortToggle.setAttribute("aria-expanded", String(open));
        return;
      }
      const sortOption = target.closest("[data-sort-option]");
      if (sortOption) {
        state.filters.sort = sortOption.getAttribute("data-sort-option");
        state.visibleCount = 12;
        renderPlaces();
        return;
      }
      const filter = target.closest("[data-filter]");
      if (filter) {
        const group = filter.getAttribute("data-filter");
        const value = filter.getAttribute("data-value");
        if (group === "cat" || group === "mood") {
          const key = group === "cat" ? "cats" : "moods";
          if (value === "all") state.filters[key] = [];
          else {
            const current = state.filters[key];
            state.filters[key] = current.includes(value) ? current.filter((x) => x !== value) : current.concat(value);
          }
        }
        state.visibleCount = 12;
        syncFiltersToUrl();
        renderPlaces();
        return;
      }
      const budget = target.closest("[data-budget-min]");
      if (budget) {
        state.filters.minPrice = Number(budget.getAttribute("data-budget-min")) || 0;
        const maxAttr = budget.getAttribute("data-budget-max");
        state.filters.maxPrice = maxAttr === "" ? null : Number(maxAttr);
        state.visibleCount = 12;
        syncFiltersToUrl();
        renderPlaces();
        return;
      }
      if (target.closest("[data-filter-reset]")) {
        state.filters = { cats: [], moods: [], minPrice: 0, maxPrice: null, q: "", sort: state.filters.sort };
        state.visibleCount = 12;
        syncFiltersToUrl();
        renderPlaces();
        return;
      }
      if (target.closest("[data-load-more]")) {
        state.visibleCount += 12;
        renderCatalogResults();
        return;
      }
      const share = target.closest("[data-share]");
      if (share) {
        sharePlace(share.getAttribute("data-share"));
        return;
      }

      const card = target.closest("[data-href]");
      if (card && !target.closest("a, button")) {
        location.hash = card.getAttribute("data-href");
        return;
      }
      const navLink = target.closest("#main-nav a");
      if (navLink) {
        const nav = $("#main-nav");
        if (nav) nav.classList.remove("open");
        const menu = $('[data-action="menu"]');
        if (menu) menu.setAttribute("aria-expanded", "false");
      }
    });

    document.addEventListener("keydown", (event) => {
      if (event.key === "Escape") {
        closeModal();
        const nav = $("#main-nav");
        if (nav) nav.classList.remove("open");
        return;
      }
      if (event.key === "Enter" && event.target.matches("[data-href]")) {
        location.hash = event.target.getAttribute("data-href");
      }
      if (event.key === "/" && !["INPUT", "TEXTAREA", "SELECT"].includes(document.activeElement.tagName)) {
        const search = $("#search-input");
        if (search) {
          event.preventDefault();
          search.focus();
        }
      }
    });

    document.addEventListener("input", (event) => {
      if (event.target.id === "search-input") {
        state.filters.q = event.target.value;
        state.visibleCount = 12;
        renderCatalogResults();
        syncFiltersToUrl();
      }
    });

    document.addEventListener("change", (event) => {
      if (event.target.id === "plan-custom-budget") {
        const raw = event.target.value.trim();
        const value = raw === "" ? 0 : Math.max(0, Number(raw) || 0);
        state.plan = { budget: value, attempt: 0, party: state.plan ? state.plan.party : "any", nonce: (state.plan ? state.plan.nonce : 0) + 1 };
        renderPlanModal();
        return;
      }
      if (event.target.id === "budget-max") {
        const raw = event.target.value.trim();
        const value = raw === "" ? null : Math.max(0, Number(raw));
        state.filters.minPrice = 0;
        state.filters.maxPrice = Number.isFinite(value) ? value : null;
        state.visibleCount = 12;
        syncFiltersToUrl();
        renderPlaces();
      }
    });

    window.addEventListener("hashchange", () => {
      closeModal();
      renderRoute(true);
    });

    window.addEventListener("online", () => {
      setOffline(false);
      loadFeed(true, true);
    });
    window.addEventListener("offline", () => setOffline(true));

    document.addEventListener("visibilitychange", () => {
      if (document.visibilityState === "visible" && state.feed) {
        const age = Date.now() - new Date(state.feed.updatedAt).getTime();
        if (age > 15 * 60 * 1000) loadFeed(true, true);
      }
    });
  }

  function init() {
    try {
      const savedLang = localStorage.getItem(LANG_KEY);
      if (savedLang === "ru" || savedLang === "en") state.lang = savedLang;
      const savedTheme = localStorage.getItem(THEME_KEY);
      if (savedTheme === "light" || savedTheme === "dark") state.theme = savedTheme;
      const saved = JSON.parse(localStorage.getItem(SAVED_KEY) || "[]");
      if (Array.isArray(saved)) state.saved = saved.filter((x) => typeof x === "string");
    } catch (_) {}
    document.documentElement.dataset.theme = state.theme;
    document.documentElement.lang = state.lang;
    const meta = document.querySelector('meta[name="theme-color"]');
    if (meta) meta.setAttribute("content", state.theme === "dark" ? "#09090c" : "#f5f4f8");

    state.bootAt = Date.now();
    applyStaticI18n();
    renderHeader();
    renderFooter();
    bindEvents();
    if (location.hostname === "localhost" || location.hostname === "127.0.0.1") checkServer();
    loadFeed(false, true);
    setTimeout(hideSplash, 5000);

    if ("serviceWorker" in navigator && location.protocol.startsWith("http")) {
      navigator.serviceWorker.register("sw.js").then((reg) => reg.update()).catch(() => {});
    }

    setInterval(() => {
      if (document.visibilityState === "visible" && state.feed) loadFeed(true, true);
    }, 30 * 60 * 1000);
  }

  init();
})();
