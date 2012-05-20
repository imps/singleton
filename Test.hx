package;

class TestClass implements Singleton
{
    private var some_int:Int;
    public var another_int:Int;

    public var some_prop(default, default):Int;

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

    public static function another_unrelated():Int
    {
        return TestClass.unrelated();
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
        this.assertEquals(5, TestClass.increment_some());
        this.assertEquals(6, TestClass.increment_another());
        this.assertEquals(6, TestClass.increment_some());
    }

    public function test_multiarg_funs()
    {
        this.assertEquals(42, TestClass.set_prop(42));
    }

    public function test_unrelated()
    {
        var sfields = Type.getClassFields(TestClass);
        this.assertTrue(Lambda.has(sfields, "unrelated"));
        this.assertEquals(666, TestClass.another_unrelated());
    }

    public function test_properties()
    {
        TestClass.set_prop(9247);
        this.assertEquals(9247, TestClass.some_prop);

        TestClass.some_prop = 999;
        this.assertEquals(999, TestClass.some_prop);
    }

    public function test_var_property()
    {
        TestClass.another_int = 456;
        this.assertEquals(456, TestClass.another_int);
        TestClass.increment_another();
        this.assertEquals(457, TestClass.another_int);
    }

    public function test_private()
    {
        var sfields = Type.getClassFields(TestClass);

        this.assertFalse(Lambda.has(sfields, "not_accessible"));
        this.assertFalse(Lambda.has(sfields, "some_int"));

        this.assertTrue(Lambda.has(sfields, "increment_some"));
        this.assertTrue(Lambda.has(sfields, "another_int"));
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
