declare const React: {
  createElement: (...args: any[]) => any;
  Fragment: any;
  useState<T>(initial: T | (() => T)): [T, (value: T | ((previous: T) => T)) => void];
  useEffect(effect: () => void | (() => void), dependencies?: readonly unknown[]): void;
  useMemo<T>(factory: () => T, dependencies: readonly unknown[]): T;
  useRef<T>(initial: T): { current: T };
  useCallback<T extends (...args: any[]) => any>(callback: T, dependencies: readonly unknown[]): T;
};
declare const ReactDOM: { createRoot(element: Element | DocumentFragment): { render(node: any): void; unmount(): void } };
declare namespace JSX {
  interface IntrinsicElements { [elementName: string]: any }
  interface ElementChildrenAttribute { children: {} }
}
