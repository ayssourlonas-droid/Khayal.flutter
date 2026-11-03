"""عزل بيانات كل لعبة: كل الألعاب على نفس النطاق، فنضيف بادئة (slug) لمفاتيح
localStorage وأسماء IndexedDB وCache API حتى لا تتصادم ألعاب مختلفة.
يُحقن سكربت صغير أول <head> في كل صفحة HTML (قبل أي سكربت للعبة)."""
import re
from pathlib import Path

MARK = "/*khayal-iso*/"

JS = r"""(function(){try{
var P=__PREFIX__;
if(window.__khayalIso)return;window.__khayalIso=1;
var real=window.localStorage;
var proxy=new Proxy({},{
 get:function(_,k){
  if(k==='getItem')return function(x){var v=real.getItem(P+String(x));return v;};
  if(k==='setItem')return function(x,v){real.setItem(P+String(x),String(v));};
  if(k==='removeItem')return function(x){real.removeItem(P+String(x));};
  if(k==='clear')return function(){var d=[];for(var i=0;i<real.length;i++){var n=real.key(i);if(n.indexOf(P)===0)d.push(n);}d.forEach(function(n){real.removeItem(n);});};
  if(k==='key')return function(i){var c=-1;for(var j=0;j<real.length;j++){var n=real.key(j);if(n.indexOf(P)===0){c++;if(c===i)return n.slice(P.length);}}return null;};
  if(k==='length'){var c=0;for(var j=0;j<real.length;j++){if(real.key(j).indexOf(P)===0)c++;}return c;}
  if(typeof k==='symbol')return undefined;
  var v=real.getItem(P+k);return v===null?undefined:v;},
 set:function(_,k,v){real.setItem(P+String(k),String(v));return true;},
 deleteProperty:function(_,k){real.removeItem(P+String(k));return true;},
 has:function(_,k){return real.getItem(P+String(k))!==null;},
 ownKeys:function(){var o=[];for(var j=0;j<real.length;j++){var n=real.key(j);if(n.indexOf(P)===0)o.push(n.slice(P.length));}return o;},
 getOwnPropertyDescriptor:function(_,k){var v=real.getItem(P+String(k));return v===null?undefined:{value:v,writable:true,enumerable:true,configurable:true};}
});
Object.defineProperty(window,'localStorage',{get:function(){return proxy;},configurable:true});
if(window.indexedDB){
 var idb=window.indexedDB,oo=idb.open.bind(idb),od=idb.deleteDatabase.bind(idb);
 idb.open=function(n,v){return v===undefined?oo(P+n):oo(P+n,v);};
 idb.deleteDatabase=function(n){return od(P+n);};
 if(idb.databases){var odb=idb.databases.bind(idb);idb.databases=function(){return odb().then(function(l){return l.filter(function(d){return d.name.indexOf(P)===0;}).map(function(d){return {name:d.name.slice(P.length),version:d.version};});});};}
}
if(window.caches){
 var C=window.caches,co=C.open.bind(C),ch=C.has.bind(C),cd=C.delete.bind(C);
 C.open=function(n){return co(P+n);};C.has=function(n){return ch(P+n);};C.delete=function(n){return cd(P+n);};
}
}catch(e){}})();"""


def script_for(slug: str) -> str:
    prefix = "khayal:" + re.sub(r"[^a-z0-9._-]", "_", slug.lower()) + ":"
    return "<script>" + MARK + JS.replace("__PREFIX__", repr(prefix)) + "</script>"


def inject(site: Path, slug: str):
    """يعيد عدد الصفحات المعدّلة. يتخطى ملفات HTML غير UTF-8 أو المحقونة سابقاً."""
    tag = script_for(slug)
    n = 0
    for p in site.rglob("*"):
        if not p.is_file() or p.suffix.lower() not in (".html", ".htm"):
            continue
        try:
            t = p.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        if MARK in t:
            continue
        m = re.search(r"<head[^>]*>", t, re.I) or re.search(r"<html[^>]*>", t, re.I)
        if m:
            t = t[:m.end()] + tag + t[m.end():]
        else:
            dm = re.match(r"\s*<!doctype[^>]*>", t, re.I)
            i = dm.end() if dm else 0
            t = t[:i] + tag + t[i:]
        p.write_text(t, encoding="utf-8")
        n += 1
    return n
