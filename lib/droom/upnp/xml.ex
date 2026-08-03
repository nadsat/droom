defmodule Droom.UPnP.XML do
  @moduledoc false
  # Helpers for parsing XML with `:xmerl_sax_parser` and working with the
  # simplified element shape `{tag, attrs, children}`.

  @doc """
  Parses an XML document (binary or charlist) into a simplified element tree
  of the form `{tag, attrs, children}`, or `{:error, reason}`.
  """
  @spec scan(binary() | charlist()) :: {:ok, term()} | {:error, term()}
  def scan(xml) when is_binary(xml), do: scan(String.to_charlist(xml))

  def scan(xml) when is_list(xml) do
    try do
      case :xmerl_sax_parser.stream(xml, event_fun: &build/3, event_state: []) do
        {:ok, [root], _rest} ->
          {:ok, root}

        {:ok, _stack, _rest} ->
          {:error, {:xml_parse, :unexpected_result}}

        {_tag, _location, reason, _rest, _state} ->
          {:error, {:xml_parse, reason}}
      end
    rescue
      error -> {:error, {:xml_parse, error}}
    catch
      :exit, reason -> {:error, {:xml_parse, reason}}
      :throw, reason -> {:error, {:xml_parse, reason}}
    end
  end

  @doc """
  Depth-first search for the first element whose local name is `name`.
  Accepts an element tuple, a list of children, or `nil`.
  """
  @spec find_by_name(term(), String.t()) :: term() | nil
  def find_by_name({_, _, _} = element, name) do
    if local_name(element) == name,
      do: element,
      else: find_by_name(element_children(element), name)
  end

  def find_by_name(children, name) when is_list(children) do
    Enum.find_value(children, fn
      {_, _, _} = element -> find_by_name(element, name)
      _ -> nil
    end)
  end

  def find_by_name(_, _), do: nil

  @doc "All direct children of `element` whose local name is `name`."
  @spec children_by_name(term(), String.t()) :: [term()]
  def children_by_name({_, _, children}, name) do
    Enum.filter(children, &(element?(&1) and local_name(&1) == name))
  end

  def children_by_name(_, _), do: []

  @doc "The local name (namespace prefix stripped) of a simplified element."
  @spec local_name(term()) :: String.t()
  def local_name({tag, _, _}) do
    tag
    |> Atom.to_string()
    |> String.split(":")
    |> List.last()
  end

  @doc "The concatenated text content of an element, ignoring nested elements."
  @spec text_content(term()) :: String.t()
  def text_content({_, _, content}) do
    content
    |> Enum.map(fn
      part when is_binary(part) -> part
      part when is_list(part) -> List.to_string(part)
      _ -> ""
    end)
    |> Enum.join()
  end

  def text_content(_), do: ""

  # SAX event callback that accumulates the simplified tree. The event state is
  # a stack of `{tag, attrs, reversed_content}` frames.
  defp build({:startElement, _uri, _local, qname, attrs}, _location, stack) do
    [{name_to_atom(qname), attrs_to_list(attrs), []} | stack]
  end

  defp build({:endElement, _uri, _local, _qname}, _location, stack) do
    case stack do
      [{tag, attrs, content} | parents] ->
        attach(parents, {tag, attrs, Enum.reverse(content)})

      [] ->
        []
    end
  end

  defp build({:characters, chars}, _location, [{tag, attrs, content} | stack]) do
    [{tag, attrs, [chars | content]} | stack]
  end

  defp build({:ignorableWhitespace, chars}, _location, [{tag, attrs, content} | stack]) do
    [{tag, attrs, [chars | content]} | stack]
  end

  defp build(_event, _location, stack), do: stack

  defp attach([], child), do: [child]

  defp attach([{tag, attrs, content} | stack], child) do
    [{tag, attrs, [child | content]} | stack]
  end

  defp attrs_to_list(attrs) do
    Enum.map(attrs, fn {_uri, prefix, local, value} ->
      {name_to_atom({prefix, local}), value}
    end)
  end

  defp name_to_atom({prefix, local}) do
    prefix = to_string(prefix)
    local = to_string(local)
    name = if prefix == "", do: local, else: prefix <> ":" <> local
    String.to_atom(name)
  end

  defp element_children({_, _, children}), do: children
  defp element_children(_), do: []

  defp element?({_, _, _}), do: true
  defp element?(_), do: false
end
