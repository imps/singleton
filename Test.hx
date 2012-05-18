package;

class TestClass implements Singleton
{
    private var some_int:Int;
    public var another_int:Int;

    public var some_prop(default, null):Int;

    public function new()
    {
        this.some_int = 4;
        this.another_int = 5;
    }

    private function not_accessible():Void
    {
        this.increment_some();
    }


    public function increment_some():Int
    {
        return ++this.some_int;
    }

    public function increment_another():Int
    {
        return ++this.another_int;
    }

    public function set_prop(val:Int):Int
    {
        return (this.some_prop = val);
    }

    public static function unrelated():Int
    {
        return 666;
    }
}

class SingletonTest extends haxe.unit.TestCase
{
    public function test_simple_funs()
    {
        this.assertEquals(5, TestClass.S_increment_some());
        this.assertEquals(6, TestClass.S_increment_another());
        this.assertEquals(6, TestClass.S_increment_some());
    }

    public function test_multiarg_funs()
    {
        this.assertEquals(42, TestClass.S_set_prop(42));
    }

    public function test_unrelated()
    {
        var sfields = Type.getClassFields(TestClass);
        this.assertFalse(Lambda.has(sfields, "S_unrelated"));
        this.assertTrue(Lambda.has(sfields, "unrelated"));
    }

    public function test_properties()
    {
        TestClass.S_set_prop(9247);
        this.assertEquals(9247, TestClass.S_some_prop);

        TestClass.S_some_prop = 999;
        this.assertEquals(999, TestClass.S_some_prop);
    }
}

class Test
{
    public static function main()
    {
        var runner = new haxe.unit.TestRunner();
        runner.add(new SingletonTest());
        runner.run();
    }
}
