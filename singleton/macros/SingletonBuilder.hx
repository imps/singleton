package singleton.macros;

import haxe.macro.Expr;
import haxe.macro.Type;

class SingletonBuilder
{
    var this_file:String;
    var cls:ClassType;
    var fields:Array<Field>;

    public function new(cls:ClassType, fields:Array<Field>, ?pi:haxe.PosInfos)
    {
        this.this_file = sys.io.File.getContent(pi.fileName);

        this.cls = cls;
        this.fields = fields;
    }

    /*
       Create a new Expr from a ExprDef, inserting current macro position.
     */
    private inline function mk(ed:ExprDef, ?pi:haxe.PosInfos):Expr
    {
        return {
            pos: this.get_pos(pi),
            expr: ed,
        };
    }

    /*
       Get current position within this macro file, not within the origin code
       calling the macro.
     */
    private function get_pos(?pi:haxe.PosInfos):Position
    {
        var line:Int = pi.lineNumber;
        var index:Int = null;

        while (line-- > 0)
            index = this.this_file.indexOf("\n", index) + 1;

        return haxe.macro.Context.makePosition({
            min: index,
            max: this.this_file.indexOf("\n", index),
            file: pi.fileName,
        });
    }

    /*
       Return an array of identifiers which should be the argument names that
       are to be passed through to the instance method.
     */
    private function get_call_params(fun:Function):Array<Expr>
    {
        var params:Array<Expr> = new Array();

        for (fp in fun.args) {
            var param:Expr = this.mk(EConst(CIdent(fp.name)));
            params.push(param);
        }

        return params;
    }

    /*
       Return an Expr to the current instance.
     */
    private function get_instance():Expr
    {
        var instref:Expr = this.mk(EConst(CType(this.cls.name)));
        return this.mk(EField(instref, "__singleton_instance"));
    }

    /*
       Return an Expr to the current instance and implicitly create it if it
       does not exist.
     */
    private function get_or_create_instance():Expr
    {
        var nullexpr:Expr = this.mk(EConst(CIdent("null")));
        var op:Expr = this.mk(
            EBinop(OpNotEq, this.get_instance(), nullexpr)
        );
        var clsdef:TypePath = {
            pack: this.cls.pack,
            name: this.cls.name,
            params: [],
        };
        var newcls:Expr = this.mk(ENew(clsdef, []));
        var create_new:Expr = this.mk(EBlock([newcls, this.get_instance()]));
        return this.mk(ETernary(op, this.get_instance(), create_new));
    }

    /*
       Returns a function call expression which calls a field of the instance of
       the singleton class.
     */
    private function get_instance_call(field:Field, fun:Function):Expr
    {
        var call_field:Expr = this.mk(
            EField(this.get_or_create_instance(), field.name)
        );

        var params:Array<Expr> = this.get_call_params(fun);

        return this.mk(ECall(call_field, params));
    }

    /*
       Create a new static field based on the given field with a new name and a
       different function and push it onto the fields of the current class.
     */
    private function push_funfield(field:Field, name:String, fun:Function):Void
    {
        var field:Field = {
            name: name,
            doc: field.doc,
            meta: field.meta,
            access: [AStatic, APublic],
            kind: FFun(fun),
            pos: this.get_pos(),
        };

        this.fields.push(field);
    }

    /*
       Create and push getter and setter functions for the given field onto the
       fields of the current class.
     */
    private function push_propfields(field:Field, type:Null<ComplexType>):Void
    {
        // getter

        var getter:Expr = this.mk(
            EField(this.get_or_create_instance(), field.name)
        );

        var getterfun:Function = {
            ret: type,
            params: [],
            expr: this.mk(EReturn(getter)),
            args: []
        };

        this.push_funfield(field, "__get_S_" + field.name, getterfun);

        // setter

        var instfield:Expr = this.mk(
            EField(this.get_or_create_instance(), field.name)
        );

        var value:Expr = this.mk(EConst(CIdent("value")));
        var setter:Expr = this.mk(EBinop(OpAssign, instfield, value));

        var setterfun:Function = {
            ret: type,
            params: [],
            expr: this.mk(EReturn(setter)),
            args: [{value: null, type: type, opt: false, name: "value"}],
        };

        this.push_funfield(field, "__set_S_" + field.name, setterfun);
    }

    private function create_var(field:Field, type:Null<ComplexType>):Field
    {
        this.push_propfields(field, type);

        var kind:FieldType = FProp(
            "__get_S_" + field.name,
            "__set_S_" + field.name,
            type
        );

        return {
            name: field.name,
            doc: field.doc,
            meta: field.meta,
            access: [AStatic, APublic],
            kind: kind,
            pos: this.get_pos(),
        };
    }

    /*
       Create a static wrapper of the given function/field.
     */
    private function create_fun(field:Field, fun:Function):Field
    {
        var body:Expr = this.mk(EReturn(this.get_instance_call(field, fun)));

        var fun:Function = {
            ret: fun.ret,
            params: fun.params,
            expr: body,
            args: fun.args,
        };

        return {
            name: field.name,
            doc: field.doc,
            meta: field.meta,
            access: [AStatic, APublic],
            kind: FFun(fun),
            pos: this.get_pos(),
        };
    }

    /*
       Create a new constructor or overwrite an existing one (specified by the
       index within this.fields) to automatically set the __singleton_instance
       value after instance creation.
     */
    private function patch_ctor(idx:Int):Void
    {
        var field:Field = this.fields[idx];

        // Get function value from existing constructor field
        var existing_fun:Function = switch (field.kind) {
            case FFun(f): f;
            default:
                var msg = "What!? The constructor of class " + this.cls.name;
                throw msg + " is not a function! Let's bail out... :-P";
        }

        var old_body:Expr = existing_fun.expr;

        var new_body:Expr = switch (old_body.expr) {
            case EBlock(a):
                a.push(this.mk(
                    EBinop(
                        OpAssign,
                        this.get_instance(),
                        this.mk(EConst(CIdent("this")))
                    )
                ));
                this.mk(EBlock(a));
            default:
                var msg = "Constructor function body of " + this.cls.name;
                throw msg + " is not a block element! Bailing out...";
        }

        var ctor_fun:Function = {
            ret: existing_fun.ret,
            params: existing_fun.params,
            expr: new_body,
            args: existing_fun.args,
        }

        var ctor_field:Field = {
            name: field.name,
            doc: field.doc,
            meta: field.meta,
            access: field.access,
            kind: FFun(ctor_fun),
            pos: field.pos,
        };

        // overwrite existing constructor
        this.fields[idx] = ctor_field;
    }

    /*
       Check if a given field's access is relevant to us.
     */
    private function is_irrelevant(access:Access):Bool
    {
        return switch (access) {
            case APrivate: true;
            case AStatic: true;
            default: false;
        }
    }

    /*
       Create a new class based on the current class and copy all fields to the
       new class. Returns the newly generated Type.
     */
    private function fork():Type
    {
        var name:String = this.cls.name + "__real";
        var kind:TypeDefKind = TDClass(); // TODO

        var newcls:TypeDefinition = {
            pos: this.cls.pos,
            params: [], //cls.params, TODO
            pack: this.cls.pack,
            name: name,
            meta: [], //cls.meta, TODO
            kind: kind,
            isExtern: this.cls.isExtern,
            fields: this.fields.copy(),
        }

        haxe.macro.Context.defineType(newcls);
        return haxe.macro.Context.getType(name);
    }

    /*
       Populate the class with the correspanding fields and return the new
       fields of the class.
     */
    public function build_singleton():Array<Field>
    {
        // move all fields of the current class to realcls
        var realcls = this.fork();

        // Create a static variable called __singleton_instance, which holds the
        // instance of the current class.

        var singleton_var:FieldType = FVar(
            TPath({pack: [], name: this.cls.name, params: [], sub: null}),
            null
        );

        this.fields.push({
            name: "__singleton_instance",
            doc: null,
            meta: [],
            access: [AStatic, APrivate],
            kind: singleton_var,
            pos: this.get_pos(),
        });

        // Iterate through all fields and create public static fields with a
        // S_ prefix which then call the function/properties/variables of the
        // corresponding instance.

        for (i in 0...this.fields.length) {
            var field:Field = this.fields[i];

            // skip fields which are not relevant to us
            if (Lambda.exists(field.access, this.is_irrelevant))
                continue;

            // constructor
            if (field.name == "new") {
                this.patch_ctor(i);
                continue;
            }

            // add static fields
            var newfield:Field = switch (field.kind) {
                case FVar(t, e):
                    this.create_var(field, t);
                case FProp(g, s, t, e):
                    this.create_var(field, t);
                case FFun(f):
                    this.create_fun(field, f);
            };

            this.fields.push(newfield);
        }

        return this.fields;
    }

    public static function build():Array<Field>
    {
        var cls:Null<Ref<ClassType>> = haxe.macro.Context.getLocalClass();
        var fields:Array<Field> = haxe.macro.Context.getBuildFields();

        var builder = new SingletonBuilder(cls.get(), fields);
        return builder.build_singleton();
    }
}
