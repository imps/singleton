Easy singleton instances for Haxe
---------------------------------

Usually singleton classes involve quite a bit of boilerplate code to retrieve
and implicitly create the corresponding instance, like for example:

```Haxe
class MySingletonClass
{
    ... methods here ...

    public static var __instance:MySingletonClass;

    public static function get_instance():MySingletonClass
    {
        if (MySingletonClass.__instance == null)
            MySingletonClass.__instance = new MySingletonClass();
        return MySingletonClass.__instance;
    }
}
```

So all calls to the singleton instance would look like that:

    MySingletonClass.get_instance().some_method();

Of course this could also be done using properties, but it just avoids a few
characters (two parenthesis) when retrieving the instance.

Our approach
------------

Thanks to macros we can avoid those boilerplates and repetitious code. Using
this library you define a singleton class like this:

```Haxe
class MySingletonClass implements Singleton
{
    ... methods here ...
}
```

This turns all public fields of the class into static functions which
automatically work on the right instance. So calls to the singleton instance
look like that:

    MySingletonClass.some_method();
