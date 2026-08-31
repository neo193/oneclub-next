import Link from "next/link";
import type { ButtonHTMLAttributes, ReactNode } from "react";
import { classes } from "@/lib/utils/classes";

type Variant = "primary" | "secondary" | "danger";

type CommonProps = {
  children: ReactNode;
  className?: string;
  variant?: Variant;
};

type LinkButtonProps = CommonProps & {
  href: string;
};

type NativeButtonProps = CommonProps &
  ButtonHTMLAttributes<HTMLButtonElement> & {
    href?: never;
  };

const variantClass: Record<Variant, string> = {
  primary: "button-primary",
  secondary: "button-secondary",
  danger: "button-danger",
};

export function Button(props: LinkButtonProps | NativeButtonProps) {
  const variant = props.variant ?? "secondary";
  const className = classes("button", variantClass[variant], props.className);

  if ("href" in props && props.href) {
    return (
      <Link className={className} href={props.href}>
        {props.children}
      </Link>
    );
  }

  const buttonProps = { ...props } as NativeButtonProps;
  delete buttonProps.variant;
  delete buttonProps.className;
  const children = buttonProps.children;
  delete buttonProps.children;

  return (
    <button className={className} {...buttonProps}>
      {children}
    </button>
  );
}

