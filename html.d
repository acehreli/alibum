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

    void add(XmlElement[] elements...)
    {
        this.elements ~= elements;
    }

    void add(string data)
    {
        this.data ~= data;
    }

    XmlElement addAttribute(string key, string value)
    {
        attributes[key] = value;
        return this;
    }

    override string toString() const
    {
        auto result = appender!string;

        formattedWrite(result, "<%s", tag);

        foreach (key, value; attributes) {
            formattedWrite(result, ` %s="%s"`, key, value);
        }

        formattedWrite(result, ">");

        foreach (element; elements) {
            formattedWrite(result, "%s", element);
        }

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
    this(Html html)
    {
        super("!DOCTYPE html", "");
        add(html);
    }
}

alias Html = SimpleXmlElement!"html";
alias Head = SimpleXmlElement!"head";
alias Body = SimpleXmlElement!"body";
alias Table = SimpleXmlElement!"table";
alias TableRow = SimpleXmlElement!"tr";
alias TableCell = SimpleXmlElement!"td";
alias Center = SimpleXmlElement!"center";
alias Img = SimpleXmlElement!"img";
alias Link = SimpleXmlElement!"a";
alias Style = SimpleXmlElement!"style";
alias Span = SimpleXmlElement!"span";

Center centered(XmlElement[] elements...)
{
    auto center = new Center;
    center.add(elements);
    return center;
}

Link makeLink(string href, string text)
{
    auto link = new Link([ "href" : href ]);
    link.add(text);
    return link;
}

Img makeImg(string url)
{
    return new Img([ "src" : url ]);
}
