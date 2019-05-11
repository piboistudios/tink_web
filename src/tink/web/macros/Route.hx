package tink.web.macros;

import tink.http.Method;
import tink.web.macros.Variant;
import tink.web.macros.RouteSignature;
import tink.web.macros.RouteResult;
import haxe.ds.Option;
import haxe.macro.Type;
import haxe.macro.Expr;

using tink.CoreApi;
using tink.MacroApi;

class Route {
  
  public static var metas = {
    var ret = [for (m in [GET, HEAD, OPTIONS, PUT, POST, PATCH, DELETE]) ':$m'.toLowerCase() => Some(m)];
    ret[':all'] = None;
    ret;
  }  
  
  public var field(default, null):ClassField;
  public var kind(default, null):RouteKind;
  public var signature(default, null):RouteSignature;
  public var consumes(default, null):Array<MimeType>;
  public var produces(default, null):Array<MimeType>;
  public var restricts(default, null):Array<Expr>;
  
  public function new(f, consumes, produces) {
    field = f;
    signature = new RouteSignature(f);
    switch [hasCall(f), hasSub(f)] {
      case [false, false]:
        f.pos.error('No routes on this field'); // should not happen actually
      case [true, false]:
        kind = KCall({
          statusCode: 
            switch field.meta.extract(':statusCode') {
              case []:
                macro 200;
              case [{params: [v]}]:
                v;
              case [v]:
                v.pos.error('@:statusCode must have one argument exactly');
              case v:
                v[1].pos.error('Cannot have multiple @:statusCode directives');
            },
          headers:
            [for(meta in field.meta.extract(':header'))
              switch meta {
                case {params: [name, value]}:
                  new NamedWith(name, value);
                case _:
                  meta.pos.error('@:header must have two arguments exactly');
              }
            ],
          html: 
            switch field.meta.extract(':html') {
              case []:
                None;
              case [{ pos: pos, params: [v] }]:
                Some(v);
              case [v]:
                v.pos.error('@:html must have one argument exactly');
              case v:
                v[1].pos.error('Cannot have multiple @:html directives');
            }
        });
      case [false, true]:
        kind = KSub;
      case [true, true]:
        f.pos.error('Cannot have both routing and subrouting on the same field');
    }
    this.consumes = MimeType.fromMeta(f.meta, 'consumes', consumes);
    this.produces = MimeType.fromMeta(f.meta, 'produces', produces);
    
    restricts = getRestricts([field.meta]);
  }
  
  
  public function getPayload():Payload {
    var payload = [];
    var i = 0;
    for(arg in signature.args2) {
      switch arg.kind {
        case AKSingle(ATParam(kind)):
          payload.push({id: i++, access: Plain(arg.name), type: arg.type, kind: kind});
        case AKObject(fields):
          for(field in fields)
            switch field.target {
              case ATParam(kind):
                payload.push({id: i++, access: Drill(arg.name, field.name), type: field.type, kind: kind});
              case _: // skip
            }
        case _: // skip
      }
    }
    return new Payload(field.pos, payload);
  }
  // public function getPayload():RoutePayload {
  //   var compound = new Array<Named<Type>>(),
  //       separate = new Array<Field>();
        
        
  //   for (arg in signature.args) 
  //     switch arg.kind {
  //       case AKParam(t, _ == loc => true, kind):
  //         switch kind {
  //           case PCompound:
  //             compound.push(new Named(arg.name, t));
  //           case PSeparate:
  //             separate.push({
  //               name: arg.name,
  //               pos: field.pos,
  //               kind: FVar(t.toComplex()),
  //             });     
  //         }
  //       default:
  //   }
    
  //   var locName = loc.getName().substr(1).toLowerCase();    
    
  //   return 
  //     switch [compound, separate] {
  //       case [[], []]: 
          
  //         Empty;
          
  //       case [[v], []]: 
          
  //         SingleCompound(v.name, v.value);
          
  //       case [[], v]: 
        
  //         Mixed(separate, compound, TAnonymous(separate));
          
  //       default:
  //         //trace(TAnonymous(separate).toString());
  //         var fields = separate.copy();
          
  //         for (t in compound)
  //           switch t.value.reduce().toComplex() {
  //             case TAnonymous(f):
  //               for (f in f)
  //                 fields.push(f);
  //             default:
  //               field.pos.error('If multiple types are defined for $locName then all must be anonymous objects');
  //           }          
            
  //         Mixed(separate, compound, TAnonymous(fields));
  //     }
  // }
  
  public static function hasWebMeta(f:ClassField) {
    return hasSub(f) || hasCall(f);
  }
  
  public static function hasCall(f:ClassField) {
    for (m in metas.keys()) if (f.meta.has(m)) return true;
    return false;
  }
  
  public static function hasSub(f:ClassField) {
    return f.meta.has(':sub');
  }
  
  // TODO: move this to somewhere
  public static function getRestricts(meta:Array<MetaAccess>):Array<Expr> {
    return [for(meta in meta) for (m in meta.extract(':restrict'))
      switch m.params {
        case [v]:
          v;
        case _:
          m.pos.error('@:restrict must have one parameter');
      }
    ];
  }
}

enum RouteKind {
  KSub;
  KCall(call:Call);
}

typedef Call = {
  statusCode:Expr,
  headers:Array<NamedWith<Expr, Expr>>,
  html:Option<Expr>,
}

enum RoutePayload {
  Empty;
  Mixed(separate:Array<Field>, compound:Array<Named<Type>>, sum:ComplexType);
  SingleCompound(name:String, type:Type);
}


abstract Payload(Pair<Position, Array<{id:Int, access:ArgAccess, type:Type, kind:ParamKind2}>>) {
  public inline function new(pos, arr) this = new Pair(pos, arr);
  public function group() {
    var flat = null;
    var body:Array<Field> = [];
    var query:Array<Field> = [];
    var header:Array<Field> = [];
    
    var pos = this.a;
    var arr = this.b;
    
    for(item in arr) {
      function add(to:Array<Field>, name:String) {
        to.push({
          name: '_${item.id}',
          access: [],
          meta: [
            {name: ':json', params: [macro $v{name}], pos: pos},
            {name: ':formField', params: [macro $v{name}], pos: pos},
          ],
          kind: FVar(item.type.toComplex(), null),
          pos: pos,
        });
      }
        
      switch item.kind {
        case PKBody(None):
          if(body.length > 0) pos.error('Body appeared more than once');
          flat = new Pair(item.access, item.type);
        case PKBody(Some(name)):
          if(flat != null) pos.error('Body appeared more than once');
          add(body, name);
        case PKQuery(name):
          add(query, name);
        case PKHeader(name):
          add(header, name);
      }
    }
    
    return {
      body: flat != null ? Flat(flat.a, flat.b) : Object(TAnonymous(body)),
      query: TAnonymous(query),
      header: TAnonymous(header),
    }
  }
  
  public inline function iterator() return this.b.iterator();
}

enum BodyType {
  Flat(access:ArgAccess, type:Type);
  Object(type:ComplexType);
}