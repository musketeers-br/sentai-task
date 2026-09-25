import { getContext, setContext } from 'svelte';
import type { FlowEditor } from './editor.svelte';

const KEY = Symbol('flow-editor');

export const setEditorContext = (editor: FlowEditor): FlowEditor => setContext(KEY, editor);
export const getEditorContext = (): FlowEditor => getContext<FlowEditor>(KEY);
