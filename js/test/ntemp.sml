signature WEB =
  sig
    type 'a field = ('a -> unit) -> {html:Html.html, action:unit->unit, write: 'a -> unit}

    val textfield : string field
    val intfield  : int field
    val divintfield  : int field
  end

structure Web : WEB =
  struct
    type 'a field = ('a -> unit) -> {html:Html.html, action:unit->unit, write: 'a -> unit}

    local val c = ref 0
    in fun newId() = !c before c:= !c + 1
    end

    fun get id = 
        case Js.getElementById Js.document id of
          SOME e => e
        | NONE => raise Fail ("Missing id in document: " ^ id)

    val textfield : string field = fn f : string -> unit =>
        let val id = "id" ^ Int.toString(newId())      
          fun action() =
              let val e = get id
              in Js.installEventHandler e Js.onchange (fn() => (f(Js.value e); false))
              end
        in {html=Html.$("<input type='text' id='" ^ id ^ "'>"),
            action=action,
            write = fn _ => ()}
        end

    val intfield : int field = fn f : int -> unit =>
        let val id = "id" ^ Int.toString(newId())      
          fun action() =
              let val e = get id
                fun task() =
                    case Int.fromString (Js.value e) of
                      SOME i => (f i; false)
                    | NONE => false

              in Js.installEventHandler e Js.onchange task
              end
        in {html=Html.$("<input type='text' id='" ^ id ^ "'>"),
            action=action,
            write=fn _ => ()}
        end

    val divintfield : int field = fn _ =>
        let val id = "id" ^ Int.toString(newId())      
          fun action() = ()
        in {html=Html.$("<div id='" ^ id ^ "'>?</div>"),
            action=action,
            write=fn i => Js.innerHTML (get id) (Int.toString i)}
        end

  end



local open Html infix &&
val tf_f = Web.divintfield (fn _ => ())
fun comp (i:int) = 
    let val t_f = 9 * i div 5 + 32
    in #write tf_f t_f
    end
val tf_c = Web.intfield comp
in

val page = html(body(h1($"Temperature Conversion") &&
               table (tr(th($"Temperature in Celcius:") && td(#html tf_c)) &&
                        tr(th($"Temperature in Fahrenheit:") && td(#html tf_f)))))

val () = printhtml page
val () = #action tf_c ()
end
