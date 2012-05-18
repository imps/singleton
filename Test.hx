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

    public function set_prop(val:Int):Void
    {
        this.some_prop = val;
    }

    public static function unrelated():Int
    {
        return 666;
    }
}

class SingletonTest extends haxe.unit.TestCase
{
    public function test_singleton()
    {
        this.assertEqual(TestClass.S_increment_some(), 5);
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
