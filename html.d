module html;

import std.string;
import std.format;
import std.conv;
import std.array;

class XmlElement
{
    string tag;
    string tagClosing;
    string[string] attributes;
    XmlElement[] elements;
    string data;

    this(string tag, string[string] attributes = null)
    {
        this(tag, tag, attributes);
    }

    this(string tag, string tagClosing, string[string] attributes = null)
    {
        this.tag = tag;
        this.tagClosing = tagClosing;
        this.attributes = attributes;
    }

    XmlElement add(XmlElement[] elements...)
    {
        this.elements ~= elements;
        return this;
    }

    XmlElement add(string[string] attributes...)
    {
        foreach (key, value; attributes) {
            this.attributes[key] = value;
        }
        return this;
    }

    XmlElement add(string data)
    {
        this.data ~= data;
        return this;
    }

    override string toString() const
    {
        auto result = appender!string;

        formattedWrite(result, `<%s%-( %s="%s"%|%)>`, tag, attributes);
        formattedWrite(result, "%(%s%)", elements);
        formattedWrite(result, "%s", data);

        if (!tagClosing.empty) {
            formattedWrite(result, "</%s>", tagClosing);
        }

        return result.data;
    }
}

class SimpleXmlElement(string Tag, string TagClosing = Tag) : XmlElement
{
    this(string[string] attributes = null)
    {
        super(Tag, TagClosing, attributes);
    }
}

class Document : XmlElement
{
    this(string[string] attributes = null)
    {
        super("!DOCTYPE html", "", attributes);
    }
}

alias Html = SimpleXmlElement!"html";
alias Head = SimpleXmlElement!"head";
alias Body = SimpleXmlElement!"body";
alias Table = SimpleXmlElement!"table";
alias TableRow = SimpleXmlElement!"tr";
alias TableCell = SimpleXmlElement!"td";
alias Center = SimpleXmlElement!"center";
alias Link = SimpleXmlElement!"a";
alias Style = SimpleXmlElement!"style";
alias Span = SimpleXmlElement!"span";
alias Title = SimpleXmlElement!"title";
alias Paragraph = SimpleXmlElement!"p";

class Hr : XmlElement
{
    this()
    {
        super("hr", "");
    }
}

class Break : XmlElement
{
    this()
    {
        super("br", "");
    }
}

class Img : XmlElement
{
    this(string[string] attributes = null)
    {
        super("img", "", attributes);
    }
}

class Base : XmlElement
{
    this(string[string] attributes = null){
        super("base", "", attributes);
    }
}

struct CssStyleValue
{
    string element;
    string[string] styles;

    this(string element, string[string] styles = null)
    {
        this.element = element;
        this.styles = styles;
    }

    string toString() const
    {
        return format(`%s {%-(%s:%s;%)}`, element, styles);
    }
}

XmlElement centered(XmlElement[] elements...)
{
    return (new Center).add(elements);
}

XmlElement makeLink(string href, string text = null)
{
    if (!text) {
        text = href;
    }
    return new Link([ "href" : href ]).add(text);
}

Img makeImg(string src, string alt = "image")
{
    return new Img([ "src" : src, "alt" : alt ]);
}

XmlElement makeTitle(string title)
{
    return (new Title).add(title);
}

Base makeBase(string href)
{
    return new Base([ "href" : href ]);
}
