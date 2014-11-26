package mithril.macros;

#if macro
import haxe.macro.Expr;
import haxe.macro.Context;
import haxe.macro.Type;

using haxe.macro.ExprTools;
using Lambda;

class ModuleBuilder
{
	// Types: 1 - View, 2 - Controller, 3 - Module
	@macro public static function build(type : Int) : Array<Field>
	{
		var c : ClassType = Context.getLocalClass().get();
		if (c.meta.has(":ModuleProcessed")) return null;
		c.meta.add(":ModuleProcessed",[],c.pos);

		var fields = Context.getBuildFields();

		var propWarning = function(f : Field) {
			if (Lambda.exists(f.meta, function(m) return m.name == "prop")) {
				Context.warning("@prop only works with var", f.pos);
			}
		}

		for(field in fields) switch(field.kind) {
			case FFun(f):
				f.expr.iter(replaceM);
				if (type & 2 == 2 && field.name == "controller") injectModule(f);
				if (type & 3 == 3 && field.name == "view") implyViewArgument(f, Context.getLocalType());
				propWarning(field);
			case FVar(t, e):
				var prop = field.meta.find(function(m) return m.name == "prop");
				if (prop != null) {
					field.meta.remove(prop);
					field.access.push(Access.ADynamic);
					field.kind = propFunction(t, e);
				}
			case _:
				propWarning(field);
		}

		return fields;
	}

	/**
	 * Change: @prop public var description : String;
	 * To:     public dynamic function description(?v : String) : String return v;
	 */
	static private function propFunction(t : Null<ComplexType>, e : Expr) : FieldType {
		var f = {
			ret: t,
			params: null,
			expr: macro return v,
			args: [{
				value: null,
				type: t,
				opt: true,
				name: "v"
			}]
		}

		return FFun(f);
	}

	private static function replaceM(e : Expr) {
		// Autocompletion for m()
		if (Context.defined("display")) {
			switch(e.expr) {
				case ECall(e, params):
					for (p in params) {
						switch(p.expr) {
							case EDisplay(e2, isCall):
								switch(e2) {
									case macro m:
										if(Context.defined("js"))
											e2.expr = (macro mithril.M.m).expr;
										else
											e2.expr = (macro mithril.M.instance.m).expr;
									case _:
								}
							case _:
						}
					}
				case _:
			}
		}

		switch(e) {
			case macro M($a, $b, $c), macro m($a, $b, $c):
				e.iter(replaceM);
				if(Context.defined("js"))
					e.expr = (macro mithril.M.m($a, $b, $c)).expr;
				else
					e.expr = (macro mithril.M.instance.m($a, $b, $c)).expr;

			case macro M($a, $b), macro m($a, $b):
				e.iter(replaceM);
				if(Context.defined("js"))
					e.expr = (macro mithril.M.m($a, $b)).expr;
				else
					e.expr = (macro mithril.M.instance.m($a, $b)).expr;
			case macro M($a), macro m($a):
				if(Context.defined("js"))
					e.expr = (macro mithril.M.m($a)).expr;
				else
					e.expr = (macro mithril.M.instance.m($a)).expr;			
			case macro M.$a if(!Context.defined("js")):
				e.expr = (macro M.instance.$a).expr;
			case _:
				e.iter(replaceM);
		}
	}

	private static function implyViewArgument(f : Function, t : Type) {
		if(f.args.length > 0) return;
		f.args.push({
			value: null,
			type: Context.toComplexType(t),
			opt: false,
			name: "__controller"
		});
	}

	private static function injectModule(f : Function) {
		if (f.expr == null) return;
		switch(f.expr.expr) {
			case EBlock(exprs):
				// If an anonymous object is used, don't call it.
				if(Context.defined("js"))
					exprs.unshift(macro
						if (mithril.M.__cm != this && Type.typeof(mithril.M.__cm) != Type.ValueType.TObject)
							return mithril.M.__cm.controller()
					);
				else
					exprs.unshift(macro
						if (mithril.M.instance.__cm != this && Type.typeof(mithril.M.instance.__cm) != Type.ValueType.TObject)
							return mithril.M.instance.__cm.controller()
					);
				exprs.push(macro return this);
			case _:
				f.expr = {expr: EBlock([f.expr]), pos: f.expr.pos};
				injectModule(f);
		}
	}
}
#end