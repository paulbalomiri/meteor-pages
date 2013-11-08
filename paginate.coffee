@__Pages = class Pages
  constructor: (collection, settings = {}) ->
    @setCollection collection
    @setId collection
    Pages.prototype.paginations[@name] = @
    for key, value of settings
      @set key, value
    @setRouter()
    if Meteor.isServer
      @setMethods()
      Meteor.publish @name, @_getPage.bind @
    else
      @setTemplates()
      @countPages()
      if Pages.prototype._firstCall
        @watchman()
      @sess "currentPage", 1
      @sess "ready", true
    Pages.prototype._firstCall = false
    return @
  dataMargin: 3
  filters: {}
  infinite: false
  itemTemplate: "_pagesItemDefault"
  navShowFirst: false
  navShowLast: false
  onReloadPage1: false
  pageSizeLimit: 60 #Unavailable to the client
  paginationMargin: 3
  perPage: 10
  requestTimeout: 2
  route: "/page/"
  router: false
  routerTemplate: "pages"
  sort: {}
  templateName: "" #Defaults to collection name
  #maxChangeRate: 1000
  availableSettings:
    dataMargin: Number
    filters: Object
    infinite: Boolean
    itemTemplate: String
    navShowFirst: Boolean
    navShowLast: Boolean
    onReloadPage1: Boolean
    paginationMargin: Number
    perPage: Number
    requestTimeout: Number
    route: String
    router: true #Any type. Use only in comparisons. String or Boolean expected
    routerTemplate: String
    sort: Object
  _firstCall: true
  _ready: true
  _currentPage: 1
  cache: {}
  collections: {}
  waiters: {}
  timeouts: {}
  subscriptions: {}
  queue: []
  pagesRequested: []
  pagesReceived: []
  paginations: {}
  currentSubscription: null
  methods:
    "CountPages": ->
      Math.ceil @Collection.find(@filters, 
        sort: @sort
      ).count() / @perPage
    "Set": (k, v = undefined) ->
      if v?
        @set k, v
      else
        for _k, _v of k
          @set _k, _v
  setId: (name) ->
    if name of Pages.prototype.paginations
      n = name.match /[0-9]+$/
      if n? 
        name = name[0 .. n[0].length] + (parseInt(n) + 1)
      else
        name = name + "2"
    @id = "pages." + name
    @name = name
  setCollection: (collection) ->
    try
      @Collection = new Meteor.Collection collection
      Pages.prototype.collections[@name] = @Collection
    catch e
      @Collection = Pages.prototype.collections[@name]
  setMethods: ->
    nm = {}
    for n, f of @methods
      nm[@id + n] = f.bind @
    @methods = nm
    Meteor.methods @methods
  setRouter: ->
    if @router is "iron-router"
      pr = "#{@route}:n"
      t = @routerTemplate
      self = @
      Router.map ->
        @route "home",
            path: "/"
            template: t
            before: ->
                self.sess "currentPage", 1
        @route "page",
            path: pr
            template: t
            before: ->
                self.sess "currentPage", parseInt(@params.n)
  setTemplates: ->
    name = if @templateName is "" then @name else @templateName
    Template[name].pagesNav = (->
      Template['_pagesNav'] @
    ).bind @
    Template[name].pages = (->
      Template['_pagesPage'] @
    ).bind @
  defaults: (k, v) ->
    if v?
      Pages.prototype[k] = v
    else
      Pages.prototype[k]
  countPages: ->  
    Meteor.call "#{@id}CountPages", ((e, r) ->
      @sess "totalPages", r
    ).bind(@)
  currentPage: ->
    if Meteor.isClient and @sess("currentPage")?
      @sess "currentPage"
    else 
      @_currentPage
  isReady: ->
    @_ready
  ready: (p) ->
    @_ready = true
    if p == true or p is @currentPage() and Session?
      @sess "ready", true
  stopSubscriptions: ->
    for k, v of @subscriptions
      try
        @Collection._collection.remove()
      catch e
      @subscriptions[k].stop()
      delete @subscriptions[k]
  loading: (p) ->
    unless @infinite
      @stopSubscriptions()
      @_ready = false
      if p is @currentPage() and Session?
        @sess "ready", false
  logRequest: (p) ->
    @timeLastRequest = @now()
    @loading p
    unless p in @pagesRequested
      @pagesRequested.push(p)
  logResponse: (p) ->
    unless p in @pagesReceived
      @pagesReceived.push(p)
  clearQueue: ->
    @queue = []
    #@pagesRequested = []
    #@pagesReceived = []
  sess: (k, v) ->
    k = "#{@id}.#{k}"
    #console.log k, v
    if v?
      Session.set k, v
    else
      Session.get k
  set: (k, v = undefined) ->
    if Meteor.isClient
      Meteor.call "#{@id}Set", k, v, @reload.bind(@)
    """
    Overloading must be implemented both here and in set() method for full support for hash of options and single callback
    """
    if v?
      @_set k, v
    else
      for _k, _v of k
        @_set _k, _v
    true
  _set: (k, v) ->
    if k of @availableSettings
      if @availableSettings[k] isnt true
        check v, @availableSettings[k]
      @[k] = v
    else
      new Meteor.Error 400, "Setting not available."
  now: ->
    (new Date()).getTime()
  reload: ->
    @clearCache()
    Meteor.call "#{@id}CountPages", ((e, total) ->
      @sess "totalPages", total
      p = @currentPage()
      p = 1 if @onReloadPage1 or p > total
      @sess "currentPage", false
      @sess "currentPage", p
    ).bind @
  clearCache: ->
    @cache = {}
    @pagesRequested = []
    @pagesReceived = []
  onData: (page) ->
    #console.log @name, page, 'READY'
    @currentSubscription = page
    @logResponse page
    @ready(page)
    @cache[page] = @_getPage(1).fetch()
    @checkQueue()
  checkQueue: ->
    if @queue.length
      i = @queue.shift() until i in @neighbors(@currentPage()) or not @queue.length
      @recvPage i, false
  _getPage: (page) ->
    #console.log(page, ((page - 1) * @perPage), @perPage, @sort) if Meteor.isServer
    #console.log "Fetching last result"
    @perPage = if @pageSizeLimit < @perPage then @pageSizeLimit else @perPage
    skip = (page - 1) * @perPage
    skip = 0 if skip < 0
    @Collection.find @filters,
      sort: @sort
      skip: skip
      limit: @perPage
  getPage: (page) ->
    #console.log "getPage #{page}"
    unless page?
      page = @currentPage()
    page = parseInt(page)
    if Meteor.isClient
      @recvPages page
      if page of @cache
        return @cache[page]
  recvPage: (page) ->
    #console.log "recvPage #{page}"
    if page of @cache
      return
    unless @_ready
      if page is @currentPage()
        """
        If the request concerns current page, clear the queue and execute right away.
        """
        @clearQueue()
        @_ready = true
      else
        #console.log "Adding #{page} to queue" + (if isCurrent then " (current)" else " (not current)")
        return @queue.push page
    @logRequest page
    #console.log 'Subscribing to ', page
    """
    Run again if something goes wrong and the page is still needed
    """
    @timeouts[page] = setTimeout ((page) ->
      if (page not in @pagesReceived or page not in @pagesRequested) and page in @neighbors @currentPage()
        #console.log "Again #{page}"
        @recvPage page
    ).bind(@, page), @requestTimeout * 1000
    """
    Subscription may block unless deferred.
    """
    Meteor.defer ((page) ->
      @subscriptions[page] = Meteor.subscribe @name, page,
        onReady: ((page) ->
          @.onData page
        ).bind(@, page)
        onError: (e) ->
          console.log 'Error', e
    ).bind(@, page)
  recvPages: (page) ->
    #console.log "recvPages called for #{page}"
    #console.log "Neighbors list: ", @neighbors page
    for p in @neighbors page
      unless p in @pagesReceived or p of @cache
        #console.log "Requesting #{p}" + (if p is page then " (current)" else " (not current)")
        @recvPage p
  watchman: ->
    setInterval ->
      for k, v of Pages.prototype.paginations
        Pages.prototype.watch.call v
    , 1000
  watch: ->
    @checkQueue @currentPage()
  neighbors: (page) ->
    @n = [page]
    for d in [1 .. @dataMargin]
      @n.push page + d
      dd = page - d
      if dd > 0
        @n.push dd
    @n
  paginationNeighbors: ->
    page = @currentPage()
    total = @sess "totalPages"
    margin = @paginationMargin
    #console.log page, total, margin
    from = page - margin
    to = page + margin
    if from < 1
        to += 1 - from
        from = 1
    if to > total
        from -= to - total
        to = total
    from = 1 if from < 1
    to = total if to > total
    n = []
    if @navShowFirst
      n.push
        p: "«"
        n: 1
        active: ""
        disabled: if page == 1 then "disabled" else ""
    n.push
        p: "<"
        n: page - 1
        active: ""
        disabled: if page == 1 then "disabled" else ""
    for p in [from .. to]
      n.push
        p: p
        n: p
        active: if p == page then "active" else ""
        disabled: if page > total then "disabled" else ""
    n.push
        p: ">"
        n: page + 1
        active: ""
        disabled: if page >= total then "disabled" else ""
    if @navShowLast
      n.push
          p: "»"
          n: total
          active: ""
          disabled: if page >= total then "disabled" else ""
    for i, k in n
      n[k]['_p'] = @
    n
  onNavClick: (n, p) ->
    cpage = @currentPage()
    total = @sess "totalPages"
    #console.log cpage, total, n, p
    page = n
    if page <= total and page > 0
      @sess "currentPage", page
  setInfiniteTrigger: ->
    window.scroll = ->
      (window.innerHeight + window.scrollY) >= document.body.offsetHeight - 100

Meteor.Paginate = (collection, settings) ->
  new Pages collection, settings