_.extend Template['_pagesPage'],
    ready: ->
        @sess "ready"
    items: ->
        p = @getPage @sess "currentPage"
        unless p?
            return
        for i, k in p
            p[k]['_t'] = @itemTemplate
        p
    item: ->
        Template[@_t] @

_.extend Template['_pagesNav'],
    show: ->
        1 < @sess "totalPages"
    link: ->
        self = @_p
        if self.router
            p = @n
            p = 1 if p < 1
            total = self.sess "totalPages"
            p = total if p > total
            return self.route + p
        "#"
    paginationNeighbors: ->
        @sess "currentPage"
        @paginationNeighbors()
    events:
        "click a": _.throttle ( (e) ->
            n = e.target.parentNode.parentNode.parentNode.getAttribute 'data-pages'
            self = __Pages.prototype.paginations[n]
            unless self.router
                e.preventDefault()
            self.onNavClick.call self, @n, @p
        ), 1000

_.extend Template['_pagesItemDefault'],
    properties: ->
        A = []
        for k, v of @
            unless k in ["_id", "_t"]
                A.push
                    name: k
                    value: v
        A