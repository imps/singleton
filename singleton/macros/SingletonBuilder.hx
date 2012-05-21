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

        while (--line > 0)
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
            name: this.get_fork_name(),
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
       Return a new static field based on the given field with a new name and a
       different function.
     */
    private function get_funfield(field:Field, name:String, fun:Function):Field
    {
        var field:Field = {
            name: name,
            doc: field.doc,
            meta: field.meta,
            access: [AStatic, APublic],
            kind: FFun(fun),
            pos: this.get_pos(),
        };

        return field;
    }

    /*
       Return getter and setter functions for the given field.
     */
    private function get_propfields(field:Field, type:Null<ComplexType>,
                                    has_getter:Bool, has_setter:Bool)
                                   :Array<Field>
    {
        var fields:Array<Field> = new Array();

        if (has_getter) {
            var getter:Expr = this.mk(
                EField(this.get_or_create_instance(), field.name)
            );

            var getterfun:Function = {
                ret: type,
                params: [],
                expr: this.mk(EReturn(getter)),
                args: []
            };

            fields.push(
                this.get_funfield(field, "__get_S_" + field.name, getterfun)
            );
        }

        if (has_setter) {
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

            fields.push(
                this.get_funfield(field, "__set_S_" + field.name, setterfun)
            );
        }

        return fields;
    }

    /*
       Create a static wrapper of the given variable or property and return the
       corresponding fields.
     */
    private function create_var(field:Field,
                                type:Null<ComplexType>):Array<Field>
    {
        // if the field is a property, determine if we have access to getter and
        // setter.
        var has_getter:Bool = true;
        var has_setter:Bool = true;

        switch (field.kind) {
            case FProp(g, s, _, _):
                has_getter = (g != "null");
                has_setter = (s != "null");
            default:
        }

        var fields = this.get_propfields(field, type, has_getter, has_setter);

        var kind:FieldType = FProp(
            has_getter ? "__get_S_" + field.name : "null",
            has_setter ? "__set_S_" + field.name : "null",
            type
        );

        fields.push({
            name: field.name,
            doc: field.doc,
            meta: field.meta,
            access: [AStatic, APublic],
            kind: kind,
            pos: this.get_pos(),
        });

        return fields;
    }

    /*
       Create a static wrapper of the given function/method and return an array
       of fields.
     */
    private function create_fun(field:Field, fun:Function):Array<Field>
    {
        var body:Expr = this.mk(EReturn(this.get_instance_call(field, fun)));

        var fun:Function = {
            ret: fun.ret,
            params: fun.params,
            expr: body,
            args: fun.args,
        };

        return [{
            name: field.name,
            doc: field.doc,
            meta: field.meta,
            access: [AStatic, APublic],
            kind: FFun(fun),
            pos: this.get_pos(),
        }];
    }

    /*
       Return the name of the copy of the current class.
     */
    private function get_fork_name():String
    {
        return this.cls.name + "__real";
    }

    /*
       Create a new class based on the current class and copy all fields to the
       new class. Returns the newly generated Type.
     */
    private function fork():Type
    {
        var name:String = this.get_fork_name();
        var kind:TypeDefKind = TDClass(); // TODO

        // make a copy of this.fields without static fields
        var fields_copy:Array<Field> = new Array();
        for (field in this.fields) {
            if (Lambda.has(field.access, AStatic))
                continue;
            fields_copy.push(field);
        }

        var newcls:TypeDefinition = {
            pos: this.cls.pos,
            params: [], //cls.params, TODO
            pack: this.cls.pack,
            name: name,
            meta: [], //cls.meta, TODO
            kind: kind,
            isExtern: this.cls.isExtern,
            fields: fields_copy,
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
        var real_type:ClassType;
        var real_params:Array<Type>;

        switch (realcls) {
            case TInst(t, p):
                real_type = t.get();
                real_params = p;
            default:
                throw "Yikes, something went wrong retrieving the instance of"
                    + " the newly generated class of " + this.cls.name + "!";
        }

        // the new container for the singleton statics
        var newfields:Array<Field> = new Array();

        // Create a static variable called __singleton_instance, which holds the
        // instance of the current class.

        var singleton_var:FieldType = FVar(
            TPath({
                pack: real_type.pack,
                name: real_type.name,
                params: [],
                sub: null,
            }),
            null
        );

        newfields.push({
            name: "__singleton_instance",
            doc: null,
            meta: [],
            access: [AStatic, APrivate],
            kind: singleton_var,
            pos: this.get_pos(),
        });

        // Iterate through all fields and create public static fields which then
        // call the function/properties/variables of the real instance.

        for (field in this.fields) {
            // static fields should end up in local class, not in the fork
            if (Lambda.has(field.access, AStatic)) {
                newfields.push(field);
                continue;
            }
            // skip private fields
            if (Lambda.has(field.access, APrivate))
                continue;

            // skip constructor
            if (field.name == "new")
                continue;

            // add static fields
            var to_add:Array<Field> = switch (field.kind) {
                case FVar(t, e):
                    this.create_var(field, t);
                case FProp(g, s, t, e):
                    this.create_var(field, t);
                case FFun(f):
                    this.create_fun(field, f);
            };

            for (f in to_add)
                newfields.push(f);
        }

        return newfields;
    }

    public static function build():Array<Field>
    {
        var cls:Null<Ref<ClassType>> = haxe.macro.Context.getLocalClass();
        var fields:Array<Field> = haxe.macro.Context.getBuildFields();

        var builder = new SingletonBuilder(cls.get(), fields);
        return builder.build_singleton();
    }
}
