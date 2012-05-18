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
        var create_new:Expr = this.mk(
            EBinop(OpAssign, this.get_instance(), newcls)
        );
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
            name: "S_" + field.name,
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
            name: "S_" + field.name,
            doc: field.doc,
            meta: field.meta,
            access: [AStatic, APublic],
            kind: FFun(fun),
            pos: this.get_pos(),
        };
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
       Populate the class with the correspanding fields and return the new
       fields of the class.
     */
    public function build_singleton():Array<Field>
    {
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
            //access: [AStatic, APrivate],
            access: [AStatic, APublic],
            kind: singleton_var,
            pos: this.get_pos(),
        });

        // Iterate through all fields and create public static fields with a
        // S_ prefix which then call the function/properties/variables of the
        // corresponding instance.

        var ctor:Field = null;

        for (field in this.fields) {
            // skip fields which are not relevant to us
            if (Lambda.exists(field.access, this.is_irrelevant))
                continue;

            // constructor
            if (field.name == "new") {
                ctor = field;
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
