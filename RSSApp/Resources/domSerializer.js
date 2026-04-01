// domSerializer.js — Thin DOM serializer for native Swift content extraction.
// Walks the live DOM tree and produces a compact JSON representation.
// All content-extraction intelligence lives in Swift; this script only serializes.

(function() {
    'use strict';

    var MAX_DEPTH = 30;
    var MAX_NODES = 5000;
    var nodeCount = 0;

    // Tags that never carry article content — skip entirely.
    var SKIP_TAGS = {
        'script': true, 'style': true, 'noscript': true,
        'svg': true, 'path': true, 'link': true, 'meta': true
    };

    function serializeNode(node, depth) {
        if (nodeCount >= MAX_NODES || depth > MAX_DEPTH) return null;

        // Text node
        if (node.nodeType === 3) {
            var text = node.nodeValue;
            if (!text || !text.trim()) return null;
            nodeCount++;
            return { t: '#text', txt: text };
        }

        // Only process element nodes
        if (node.nodeType !== 1) return null;

        var tag = node.tagName.toLowerCase();
        if (SKIP_TAGS[tag]) return null;

        nodeCount++;
        var obj = { t: tag };

        // Attributes — only include when present and non-empty
        var id = node.id;
        if (id) obj.id = id;

        var cls = node.className;
        if (cls && typeof cls === 'string') obj.cls = cls;

        var role = node.getAttribute('role');
        if (role) obj.role = role;

        if (tag === 'a') {
            var href = node.getAttribute('href');
            if (href) obj.href = href;
        }

        if (tag === 'img') {
            var src = node.getAttribute('src');
            if (src) obj.src = src;
            var alt = node.getAttribute('alt');
            if (alt) obj.alt = alt;
        }

        // Visibility — check cheap properties first to avoid expensive getComputedStyle.
        if (node.getAttribute('aria-hidden') === 'true' || node.hidden) {
            obj.vis = false;
        } else {
            var style = window.getComputedStyle(node);
            if (style.display === 'none' || style.visibility === 'hidden') {
                obj.vis = false;
            }
        }

        // Children
        var children = [];
        var childNodes = node.childNodes;
        for (var i = 0; i < childNodes.length; i++) {
            var serialized = serializeNode(childNodes[i], depth + 1);
            if (serialized) children.push(serialized);
        }
        if (children.length > 0) obj.c = children;

        return obj;
    }

    function extractMeta() {
        var meta = {};
        var tags = document.querySelectorAll('meta[property], meta[name]');
        var wanted = {
            'og:title': true, 'og:description': true, 'og:image': true,
            'article:author': true, 'article:published_time': true,
            'twitter:title': true, 'description': true, 'author': true
        };
        for (var i = 0; i < tags.length; i++) {
            var key = tags[i].getAttribute('property') || tags[i].getAttribute('name');
            var val = tags[i].getAttribute('content');
            if (key && val && wanted[key]) {
                meta[key] = val;
            }
        }
        return Object.keys(meta).length > 0 ? meta : null;
    }

    function serializeDOM() {
        nodeCount = 0;

        var htmlEl = document.documentElement;
        var lang = htmlEl ? htmlEl.getAttribute('lang') : null;

        var body = document.body ? serializeNode(document.body, 0) : null;
        if (!body) {
            body = { t: 'body' };
        }

        var result = {
            title: document.title || '',
            url: window.location.href || '',
            lang: lang || null,
            meta: extractMeta(),
            body: body
        };

        return JSON.stringify(result);
    }

    // When loaded as a WKUserScript, auto-post the result.
    // When called via evaluateJavaScript, return the string.
    if (window.webkit && window.webkit.messageHandlers &&
        window.webkit.messageHandlers.domSerialized) {
        window.webkit.messageHandlers.domSerialized.postMessage(serializeDOM());
    }

    // Expose globally so evaluateJavaScript("serializeDOM()") works.
    window.serializeDOM = serializeDOM;

    // Return result for immediate evaluateJavaScript calls.
    return serializeDOM();
})();
