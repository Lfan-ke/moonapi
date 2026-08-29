///|
/// A JSON-Schema type descriptor — the runtime, first-class value that stands in
/// for FastAPI's from-signature reflection. One `Schema` tree is *walked once* to
/// (a) emit a complete OpenAPI request/response body schema — objects, arrays and
/// scalars, with `required`, and named objects hoisted under `components/schemas`
/// and referenced by `$ref` — and (b) drive validation of an inbound JSON value.
/// This is the explicit, MoonBit-idiomatic equivalent of pydantic's type-driven
/// magic (cf. Rust `serde` + macros, Go struct tags + codegen). A named object
/// carries its fields *inline*, so the same tree is fully self-describing for
/// validation; the name is used only to deduplicate it into `components` on emit.
pub(all) enum Schema {
  SStr
  SInt
  SFloat
  SBool
  SNull
  SArray(Schema)
  SObject(ObjectSchema)
  // A closed value set (← a Python `Enum` / `typing.Literal`): the base scalar
  // whose `type` is still emitted, plus the allowed values as raw `Json`.
  SEnum(Schema, Array[Json])
} derive(Eq)

///|
/// The body of an object schema: its component `name` (empty = an anonymous
/// inline object; non-empty = hoisted to `components/schemas` and referenced),
/// its ordered `fields`, and an optional `description`.
pub(all) struct ObjectSchema {
  name : String
  fields : Array[Field]
  description : String
} derive(Eq)

///|
/// One field of an object schema: its `name`, its `schema`, whether it is
/// `required`, and an optional `description`.
pub(all) struct Field {
  name : String
  schema : Schema
  required : Bool
  description : String
  constraints : Array[Constraint]
} derive(Eq)

///|
/// Build a field. `required` defaults to `true` (FastAPI treats a field without
/// a default as required). `constraints` are the Pydantic-style value constraints
/// (`ge`/`le`/`min_length`/`pattern`/…) that are both emitted into the field's
/// OpenAPI schema and enforced when validating an inbound value.
pub fn Field::new(
  name : String,
  schema : Schema,
  required? : Bool = true,
  description? : String = "",
  constraints? : Array[Constraint] = [],
) -> Field {
  { name, schema, required, description, constraints, }
}

///|
/// A named object schema: hoisted to `components/schemas` under `name` and
/// referenced by `$ref` wherever it is used.
pub fn Schema::object(name : String, fields : Array[Field]) -> Schema {
  SObject({ name, fields, description: "", })
}

///|
/// An array schema whose elements all conform to `item`.
pub fn Schema::array(item : Schema) -> Schema {
  SArray(item)
}

///|
/// The `impl`-able version of a type's descriptor. A user struct implements it —
/// the value is ignored; it exists so descriptor-carrying code can be generic
/// over "a type that knows its own schema". The primary, mctl-friendly shape is
/// still a plain associated function `T::schema() -> Schema` (no instance needed,
/// mirroring FastAPI referencing the model *class*); this trait bridges to it.
pub(open) trait ToSchema {
  fn to_schema(Self) -> Schema
}

///|
/// The schema of any `ToSchema` type, without needing a value of it materialised
/// at the call site beyond the one handed in — the generic entry point.
pub fn[T : ToSchema] schema_of(x : T) -> Schema {
  ToSchema::to_schema(x)
}

// -- emission (descriptor tree -> OpenAPI JSON) -------------------------------

///|
/// Where `$ref`s point, which differs between spec families: OpenAPI 3.x hoists
/// schemas under `#/components/schemas/`, Swagger 2.0 under `#/definitions/`.
fn ref_base(v : OpenApiVersion) -> String {
  match v {
    Swagger20 => "#/definitions/"
    _ => "#/components/schemas/"
  }
}

///|
/// A bare `{"type": t}` scalar schema object.
fn scalar_schema(t : String) -> Json {
  let m : Map[String, Json] = Map([("type", t.to_json())])
  m.to_json()
}

///|
/// The scalar OpenAPI type name of a schema, `None` for composite schemas.
fn scalar_name(s : Schema) -> String? {
  match s {
    SStr => Some("string")
    SInt => Some("integer")
    SFloat => Some("number")
    SBool => Some("boolean")
    SNull => Some("null")
    _ => None
  }
}

///|
/// Return `j` with a `description` sibling added (legal beside `$ref` in OpenAPI
/// 3.1 / JSON-Schema 2020-12). Builds a fresh object so nothing shared mutates.
fn with_description(j : Json, desc : String) -> Json {
  match j {
    Object(m) => {
      let out : Map[String, Json] = Map([])
      for k, v in m {
        out[k] = v
      }
      out["description"] = desc.to_json()
      out.to_json()
    }
    _ => j
  }
}

///|
/// Emit `schema` as inline OpenAPI JSON, hoisting every *named* object into
/// `defs` (keyed by name) and referencing it by `$ref`. Recursion-safe: a name
/// is reserved in `defs` before its body is built, so a self-referential schema
/// terminates instead of looping.
fn emit_schema(
  schema : Schema,
  defs : Map[String, Json],
  version : OpenApiVersion,
) -> Json {
  match schema {
    SStr => scalar_schema("string")
    SInt => scalar_schema("integer")
    SFloat => scalar_schema("number")
    SBool => scalar_schema("boolean")
    SNull => scalar_schema("null")
    SArray(item) => {
      let m : Map[String, Json] = Map([
        ("type", "array".to_json()),
        ("items", emit_schema(item, defs, version)),
      ])
      m.to_json()
    }
    SObject(os) =>
      if os.name != "" {
        register_object(os, defs, version)
        let r : Map[String, Json] = Map([
          ("$ref", (ref_base(version) + os.name).to_json()),
        ])
        r.to_json()
      } else {
        object_body(os, defs, version)
      }
    SEnum(base, values) =>
      match emit_schema(base, defs, version) {
        Object(o) => {
          let m : Map[String, Json] = Map([])
          for k, v in o {
            m[k] = v
          }
          m["enum"] = values.to_json()
          m.to_json()
        }
        other => other
      }
  }
}

///|
/// Register a named object into `defs` (once), reserving its slot first so that
/// cycles through its fields resolve to the already-in-progress `$ref`.
fn register_object(
  os : ObjectSchema,
  defs : Map[String, Json],
  version : OpenApiVersion,
) -> Unit {
  match defs.get(os.name) {
    Some(_) => ()
    None => {
      defs[os.name] = Json::null()
      defs[os.name] = object_body(os, defs, version)
    }
  }
}

///|
/// The `{"type":"object","properties":{...},"required":[...]}` body of an object
/// schema, recursively emitting each field's schema (which may hoist further
/// named objects into `defs`).
fn object_body(
  os : ObjectSchema,
  defs : Map[String, Json],
  version : OpenApiVersion,
) -> Json {
  let props : Map[String, Json] = Map([])
  let required : Array[Json] = []
  for f in os.fields {
    let fs = with_constraints(
      emit_schema(f.schema, defs, version),
      f.constraints,
      version,
    )
    props[f.name] = if f.description != "" {
      with_description(fs, f.description)
    } else {
      fs
    }
    if f.required {
      required.push(f.name.to_json())
    }
  }
  let m : Map[String, Json] = Map([
    ("type", "object".to_json()),
    ("properties", props.to_json()),
  ])
  if required.length() > 0 {
    m["required"] = required.to_json()
  }
  if os.description != "" {
    m["description"] = os.description.to_json()
  }
  m.to_json()
}
