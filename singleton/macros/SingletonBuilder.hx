package singleton.macros;

import haxe.macro.Expr;
import haxe.macro.Type;

class SingletonBuilder
{
    var this_file:String;
    var cls:ClassType;
    var fields:Array<Field>;

    public function new(cls, fields, ?pi:haxe.PosInfos)
    {
        this.this_file = sys.io.File.getContent(pi.fileName);

        this.cls = cls;
        this.fields = fields;
    }

    /*
       Get current position within this macro file, not within the origin code
       calling the macro.
     */
    private function get_pos(?pi:haxe.PosInfos):Position
    {
        var line = pi.lineNumber;
        var index = null;

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
            var param:Expr = {
                pos: this.get_pos(),
                expr: EConst(CIdent(fp.name)),
            }
            params.push(param);
        }

        return params;
    }

    /*
       Returns a function call expression which calls a field of the instance of
       the singleton class.
     */
    private function get_instance_call(field:Field, fun:Function):Expr
    {
        var instref:Expr = {
            pos: this.get_pos(),
            expr: EConst(CType(this.cls.name))
        };

        var singleton:Expr = {
            pos: this.get_pos(),
            expr: EField(instref, "__singleton_instance"),
        }

        var call_field:Expr = {
            pos: this.get_pos(),
            expr: EField(singleton, field.name),
        }

        var params:Array<Expr> = this.get_call_params(fun);

        return {
            pos: this.get_pos(),
            expr: ECall(call_field, params),
        };
    }

    private function create_var(name:String, type:Null<ComplexType>):Field
    {
        // TODO
        return null;
    }

    /*
       Create a static wrapper of the given function/field.
     */
    private function create_fun(field:Field, fun:Function):Field
    {
        var body:Expr = {
            pos: this.get_pos(),
            expr: EReturn(this.get_instance_call(field, fun)),
        };

        var fun = {
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

        var singleton_var = FVar(
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
            switch (field.kind) {
                case FVar(t, e):
                    this.create_var(field.name, t);
                case FProp(g, s, t, e):
                    this.create_var(field.name, t);
                case FFun(f):
                    this.fields.push(this.create_fun(field, f));
            };
        }

        return this.fields;
    }

    public static function build():Array<Field>
    {
        var cls = haxe.macro.Context.getLocalClass();
        var fields = haxe.macro.Context.getBuildFields();

        var builder = new SingletonBuilder(cls.get(), fields);
        return builder.build_singleton();
    }
}
