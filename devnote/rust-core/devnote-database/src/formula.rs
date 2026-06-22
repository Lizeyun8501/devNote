//! 公式引擎 —— 基于 Pratt 解析器的公式求值系统
//! 支持算术运算、比较操作、逻辑短路求值、聚合函数(SUM/AVG/COUNT/MIN/MAX)和字符串函数
//!
//! 借鉴 Notion 的公式系统
//! 来源: https://www.notion.so
//! 借鉴内容: 公式字段类型、聚合函数语义(SUM/AVG/COUNT)、条件 IF 函数、字符串处理函数(LEN/UPPER/LOWER/TRIM)
//!
//! Pratt 解析器设计
//! 来源: Pratt Parser (Vaughan Pratt, 1973) - "Top Down Operator Precedence"
//! 借鉴内容: binding_power 优先级绑定、左递归消除、前缀/中缀表达式统一解析框架

use serde_json;
use std::collections::HashMap;

// ==================== FormulaValue & FormulaError ====================

#[derive(Debug, Clone, PartialEq)]
pub enum FormulaError {
    DivByZero,
    TypeError {
        expected: String,
        got: String,
        operation: String,
    },
    Overflow,
    NameError(String),
    ValueError(String),
}

#[derive(Debug, Clone, PartialEq)]
pub enum FormulaValue {
    Number(f64),
    Text(String),
    Boolean(bool),
    Error(FormulaError),
    Null,
}

impl FormulaValue {
    fn as_number(&self) -> Result<f64, FormulaError> {
        match self {
            FormulaValue::Number(n) => Ok(*n),
            FormulaValue::Text(s) => s.parse::<f64>().map_err(|_| FormulaError::TypeError {
                expected: "number".into(),
                got: "text".into(),
                operation: "arithmetic".into(),
            }),
            FormulaValue::Boolean(b) => Ok(if *b { 1.0 } else { 0.0 }),
            FormulaValue::Error(e) => Err(e.clone()),
            FormulaValue::Null => Err(FormulaError::TypeError {
                expected: "number".into(),
                got: "null".into(),
                operation: "arithmetic".into(),
            }),
        }
    }

    fn as_boolean(&self) -> Result<bool, FormulaError> {
        match self {
            FormulaValue::Boolean(b) => Ok(*b),
            FormulaValue::Number(n) => Ok(*n != 0.0),
            FormulaValue::Error(e) => Err(e.clone()),
            _ => Err(FormulaError::TypeError {
                expected: "boolean".into(),
                got: self.type_name().into(),
                operation: "logical".into(),
            }),
        }
    }

    fn is_error(&self) -> bool {
        matches!(self, FormulaValue::Error(_))
    }

    fn type_name(&self) -> &'static str {
        match self {
            FormulaValue::Number(_) => "number",
            FormulaValue::Text(_) => "text",
            FormulaValue::Boolean(_) => "boolean",
            FormulaValue::Error(_) => "error",
            FormulaValue::Null => "null",
        }
    }

    fn into_json(self) -> serde_json::Value {
        match self {
            FormulaValue::Number(n) => {
                serde_json::Value::Number(serde_json::Number::from_f64(n).unwrap_or(serde_json::Number::from(0)))
            }
            FormulaValue::Text(s) => serde_json::Value::String(s),
            FormulaValue::Boolean(b) => serde_json::Value::Bool(b),
            FormulaValue::Error(e) => serde_json::Value::String(format!("#ERROR: {:?}", e)),
            FormulaValue::Null => serde_json::Value::Null,
        }
    }
}

// ==================== Token ====================

#[derive(Debug, Clone, PartialEq)]
pub enum Token {
    Number(f64),
    String(String),
    Bool(bool),
    Null,
    FieldRef(String),
    // Arithmetic
    Plus,
    Minus,
    Multiply,
    Divide,
    Modulo,
    Power,
    // Comparison
    Eq,
    Ne,
    Lt,
    Gt,
    Le,
    Ge,
    // Logical
    And,
    Or,
    Not,
    // Punctuation
    LParen,
    RParen,
    Comma,
    // Functions (case-insensitive, stored as uppercase)
    FuncCall(String),
}

// ==================== Lexer ====================

pub struct Lexer {
    input: Vec<char>,
    position: usize,
}

impl Lexer {
    pub fn new(input: &str) -> Self {
        Self {
            input: input.chars().collect(),
            position: 0,
        }
    }

    fn peek(&self) -> Option<&char> {
        self.input.get(self.position)
    }

    fn advance(&mut self) -> Option<char> {
        let ch = self.input.get(self.position).copied();
        self.position += 1;
        ch
    }

    fn skip_whitespace(&mut self) {
        while let Some(ch) = self.peek() {
            if ch.is_whitespace() {
                self.advance();
            } else {
                break;
            }
        }
    }

    fn read_number(&mut self) -> f64 {
        let start = self.position;
        while let Some(ch) = self.peek() {
            if ch.is_ascii_digit() || *ch == '.' {
                self.advance();
            } else {
                break;
            }
        }
        let s: String = self.input[start..self.position].iter().collect();
        s.parse().unwrap_or(0.0)
    }

    fn read_identifier(&mut self) -> String {
        let start = self.position;
        while let Some(ch) = self.peek() {
            if ch.is_alphanumeric() || *ch == '_' || *ch == '.' {
                self.advance();
            } else {
                break;
            }
        }
        self.input[start..self.position].iter().collect()
    }

    fn read_string(&mut self) -> String {
        self.advance(); // skip opening quote
        let start = self.position;
        while let Some(ch) = self.peek() {
            if *ch == '"' {
                break;
            }
            self.advance();
        }
        let s: String = self.input[start..self.position].iter().collect();
        self.advance(); // skip closing quote
        s
    }

    pub fn tokenize(&mut self) -> Result<Vec<Token>, String> {
        let mut tokens = Vec::new();
        loop {
            self.skip_whitespace();
            match self.peek() {
                None => break,
                Some(ch) => {
                    let token = match ch {
                        '+' => {
                            self.advance();
                            Token::Plus
                        }
                        '-' => {
                            self.advance();
                            Token::Minus
                        }
                        '*' => {
                            self.advance();
                            if matches!(self.peek(), Some(c) if *c == '*') {
                                self.advance();
                                Token::Power
                            } else {
                                Token::Multiply
                            }
                        }
                        '/' => {
                            self.advance();
                            Token::Divide
                        }
                        '%' => {
                            self.advance();
                            Token::Modulo
                        }
                        '^' => {
                            self.advance();
                            Token::Power
                        }
                        '(' => {
                            self.advance();
                            Token::LParen
                        }
                        ')' => {
                            self.advance();
                            Token::RParen
                        }
                        ',' => {
                            self.advance();
                            Token::Comma
                        }
                        '"' => Token::String(self.read_string()),
                        '0'..='9' => Token::Number(self.read_number()),
                        '=' => {
                            self.advance();
                            if matches!(self.peek(), Some(c) if *c == '=') {
                                self.advance();
                            }
                            Token::Eq
                        }
                        '!' => {
                            self.advance();
                            if matches!(self.peek(), Some(c) if *c == '=') {
                                self.advance();
                                Token::Ne
                            } else {
                                Token::Not
                            }
                        }
                        '<' => {
                            self.advance();
                            if matches!(self.peek(), Some(c) if *c == '=') {
                                self.advance();
                                Token::Le
                            } else {
                                Token::Lt
                            }
                        }
                        '>' => {
                            self.advance();
                            if matches!(self.peek(), Some(c) if *c == '=') {
                                self.advance();
                                Token::Ge
                            } else {
                                Token::Gt
                            }
                        }
                        '&' => {
                            self.advance();
                            if matches!(self.peek(), Some(c) if *c == '&') {
                                self.advance();
                            }
                            Token::And
                        }
                        '|' => {
                            self.advance();
                            if matches!(self.peek(), Some(c) if *c == '|') {
                                self.advance();
                            }
                            Token::Or
                        }
                        c if c.is_alphabetic() || *c == '_' => {
                            let ident = self.read_identifier();
                            let upper = ident.to_uppercase();
                            match upper.as_str() {
                                "TRUE" => Token::Bool(true),
                                "FALSE" => Token::Bool(false),
                                "NULL" => Token::Null,
                                "NOT" => Token::Not,
                                "AND" => Token::And,
                                "OR" => Token::Or,
                                "SUM" | "AVG" | "COUNT" | "MIN" | "MAX" | "ABS" | "ROUND"
                                | "CEIL" | "FLOOR" | "SQRT" | "POW" | "MOD" | "IF" | "CONCAT"
                                | "LEN" | "UPPER" | "LOWER" | "TRIM" => Token::FuncCall(upper),
                                _ => Token::FieldRef(ident),
                            }
                        }
                        _ => return Err(format!("Unexpected character: {}", ch)),
                    };
                    tokens.push(token);
                }
            }
        }
        Ok(tokens)
    }
}

// ==================== AST ====================

#[derive(Debug, Clone)]
pub enum Expr {
    Number(f64),
    String(String),
    Boolean(bool),
    Null,
    FieldRef(String),
    UnaryOp {
        op: UnaryOp,
        operand: Box<Expr>,
    },
    BinaryOp {
        left: Box<Expr>,
        op: BinOp,
        right: Box<Expr>,
    },
    FuncCall {
        name: String,
        args: Vec<Expr>,
    },
}

#[derive(Debug, Clone, PartialEq)]
pub enum BinOp {
    Add,
    Sub,
    Mul,
    Div,
    Mod,
    Pow,
    Eq,
    Ne,
    Lt,
    Gt,
    Le,
    Ge,
    And,
    Or,
}

#[derive(Debug, Clone, PartialEq)]
pub enum UnaryOp {
    Neg,
    Not,
}

// ==================== Pratt Parser ====================

pub struct Parser {
    tokens: Vec<Token>,
    position: usize,
}

impl Parser {
    pub fn new(tokens: Vec<Token>) -> Self {
        Self {
            tokens,
            position: 0,
        }
    }

    fn peek(&self) -> Option<&Token> {
        self.tokens.get(self.position)
    }

    fn advance(&mut self) -> Option<Token> {
        let tok = self.tokens.get(self.position).cloned();
        self.position += 1;
        tok
    }

    fn binding_power(op: &Token) -> Option<(u8, u8)> {
        match op {
            Token::Or => Some((1, 2)),
            Token::And => Some((3, 4)),
            Token::Eq | Token::Ne => Some((5, 6)),
            Token::Lt | Token::Gt | Token::Le | Token::Ge => Some((7, 8)),
            Token::Plus | Token::Minus => Some((9, 10)),
            Token::Multiply | Token::Divide | Token::Modulo => Some((11, 12)),
            Token::Power => Some((13, 12)), // right-associative
            _ => None,
        }
    }

    fn bin_op_from_token(token: &Token) -> Option<BinOp> {
        match token {
            Token::Plus => Some(BinOp::Add),
            Token::Minus => Some(BinOp::Sub),
            Token::Multiply => Some(BinOp::Mul),
            Token::Divide => Some(BinOp::Div),
            Token::Modulo => Some(BinOp::Mod),
            Token::Power => Some(BinOp::Pow),
            Token::Eq => Some(BinOp::Eq),
            Token::Ne => Some(BinOp::Ne),
            Token::Lt => Some(BinOp::Lt),
            Token::Gt => Some(BinOp::Gt),
            Token::Le => Some(BinOp::Le),
            Token::Ge => Some(BinOp::Ge),
            Token::And => Some(BinOp::And),
            Token::Or => Some(BinOp::Or),
            _ => None,
        }
    }

    pub fn parse(&mut self) -> Result<Expr, String> {
        let expr = self.parse_expr(0)?;
        if self.position < self.tokens.len() {
            return Err(format!(
                "Unexpected token after expression: {:?}",
                self.peek()
            ));
        }
        Ok(expr)
    }

    fn parse_expr(&mut self, min_bp: u8) -> Result<Expr, String> {
        let mut left = self.parse_prefix()?;

        loop {
            let op_token = match self.peek() {
                Some(t) => t.clone(),
                None => break,
            };

            let (left_bp, right_bp) = match Self::binding_power(&op_token) {
                Some(bp) => bp,
                None => break,
            };

            if left_bp < min_bp {
                break;
            }

            self.advance();
            let right = self.parse_expr(right_bp)?;
            let op = Self::bin_op_from_token(&op_token)
                .ok_or_else(|| format!("Invalid binary operator: {:?}", op_token))?;

            left = Expr::BinaryOp {
                left: Box::new(left),
                op,
                right: Box::new(right),
            };
        }

        Ok(left)
    }

    fn parse_prefix(&mut self) -> Result<Expr, String> {
        match self.peek().cloned() {
            Some(Token::Number(n)) => {
                self.advance();
                Ok(Expr::Number(n))
            }
            Some(Token::String(s)) => {
                self.advance();
                Ok(Expr::String(s))
            }
            Some(Token::Bool(b)) => {
                self.advance();
                Ok(Expr::Boolean(b))
            }
            Some(Token::Null) => {
                self.advance();
                Ok(Expr::Null)
            }
            Some(Token::FieldRef(name)) => {
                self.advance();
                // Check if this is an unknown function call: identifier followed by (
                if matches!(self.peek(), Some(Token::LParen)) {
                    let upper = name.to_uppercase();
                    return self.parse_function_call(&upper);
                }
                Ok(Expr::FieldRef(name))
            }
            Some(Token::FuncCall(name)) => {
                self.advance();
                self.parse_function_call(&name)
            }
            Some(Token::LParen) => {
                self.advance();
                let expr = self.parse_expr(0)?;
                match self.advance() {
                    Some(Token::RParen) => Ok(expr),
                    _ => Err("Expected closing parenthesis".to_string()),
                }
            }
            Some(Token::Minus) => {
                self.advance();
                let operand = self.parse_expr(14)?; // higher than any binary op
                Ok(Expr::UnaryOp {
                    op: UnaryOp::Neg,
                    operand: Box::new(operand),
                })
            }
            Some(Token::Not) => {
                self.advance();
                let operand = self.parse_expr(14)?; // higher than any binary op
                Ok(Expr::UnaryOp {
                    op: UnaryOp::Not,
                    operand: Box::new(operand),
                })
            }
            other => Err(format!("Unexpected token: {:?}", other)),
        }
    }

    fn parse_function_call(&mut self, name: &str) -> Result<Expr, String> {
        match self.peek() {
            Some(Token::LParen) => {
                self.advance();
            }
            _ => return Err(format!("Expected '(' after function name {}", name)),
        }

        let mut args = Vec::new();
        if !matches!(self.peek(), Some(Token::RParen)) {
            args.push(self.parse_expr(0)?);
            while matches!(self.peek(), Some(Token::Comma)) {
                self.advance();
                args.push(self.parse_expr(0)?);
            }
        }

        match self.advance() {
            Some(Token::RParen) => Ok(Expr::FuncCall {
                name: name.to_string(),
                args,
            }),
            _ => Err("Expected closing parenthesis".to_string()),
        }
    }
}

// ==================== Evaluator ====================

pub struct FormulaEvaluator;

impl FormulaEvaluator {
    pub fn eval(
        expr: &Expr,
        row_values: &HashMap<String, serde_json::Value>,
        all_rows: &[HashMap<String, serde_json::Value>],
    ) -> FormulaValue {
        match expr {
            Expr::Number(n) => FormulaValue::Number(*n),
            Expr::String(s) => FormulaValue::Text(s.clone()),
            Expr::Boolean(b) => FormulaValue::Boolean(*b),
            Expr::Null => FormulaValue::Null,
            Expr::FieldRef(name) => match row_values.get(name) {
                Some(v) => Self::json_to_formula_value(v),
                None => FormulaValue::Null,
            },
            Expr::UnaryOp { op, operand } => {
                let val = Self::eval(operand, row_values, all_rows);
                if val.is_error() {
                    return val;
                }
                match op {
                    UnaryOp::Neg => match val.as_number() {
                        Ok(n) => FormulaValue::Number(-n),
                        Err(e) => FormulaValue::Error(e),
                    },
                    UnaryOp::Not => match val.as_boolean() {
                        Ok(b) => FormulaValue::Boolean(!b),
                        Err(e) => FormulaValue::Error(e),
                    },
                }
            }
            Expr::BinaryOp { left, op, right } => {
                // Short-circuit for logical operators
                if *op == BinOp::And {
                    let lv = Self::eval(left, row_values, all_rows);
                    if let FormulaValue::Error(e) = lv {
                        return FormulaValue::Error(e);
                    }
                    match lv.as_boolean() {
                        Ok(false) => return FormulaValue::Boolean(false),
                        Ok(true) => {
                            let rv = Self::eval(right, row_values, all_rows);
                            if let FormulaValue::Error(e) = rv {
                                return FormulaValue::Error(e);
                            }
                            return rv
                                .as_boolean()
                                .map(FormulaValue::Boolean)
                                .unwrap_or_else(|e| FormulaValue::Error(e));
                        }
                        Err(e) => return FormulaValue::Error(e),
                    }
                }
                if *op == BinOp::Or {
                    let lv = Self::eval(left, row_values, all_rows);
                    if let FormulaValue::Error(e) = lv {
                        return FormulaValue::Error(e);
                    }
                    match lv.as_boolean() {
                        Ok(true) => return FormulaValue::Boolean(true),
                        Ok(false) => {
                            let rv = Self::eval(right, row_values, all_rows);
                            if let FormulaValue::Error(e) = rv {
                                return FormulaValue::Error(e);
                            }
                            return rv
                                .as_boolean()
                                .map(FormulaValue::Boolean)
                                .unwrap_or_else(|e| FormulaValue::Error(e));
                        }
                        Err(e) => return FormulaValue::Error(e),
                    }
                }

                let lv = Self::eval(left, row_values, all_rows);
                let rv = Self::eval(right, row_values, all_rows);

                // Propagate errors
                if let FormulaValue::Error(e) = lv {
                    return FormulaValue::Error(e);
                }
                if let FormulaValue::Error(e) = rv {
                    return FormulaValue::Error(e);
                }

                Self::eval_binary(op, lv, rv)
            }
            Expr::FuncCall { name, args } => Self::eval_function(name, args, row_values, all_rows),
        }
    }

    fn eval_binary(op: &BinOp, left: FormulaValue, right: FormulaValue) -> FormulaValue {
        match op {
            BinOp::Add => match (&left, &right) {
                (FormulaValue::Text(l), FormulaValue::Text(r)) => {
                    FormulaValue::Text(format!("{}{}", l, r))
                }
                (FormulaValue::Text(_), _) | (_, FormulaValue::Text(_)) => {
                    FormulaValue::Error(FormulaError::TypeError {
                        expected: "number".into(),
                        got: "text".into(),
                        operation: "arithmetic".into(),
                    })
                }
                _ => match (left.as_number(), right.as_number()) {
                    (Ok(l), Ok(r)) => FormulaValue::Number(l + r),
                    (Err(e), _) | (_, Err(e)) => FormulaValue::Error(e),
                },
            },
            BinOp::Sub => match (left.as_number(), right.as_number()) {
                (Ok(l), Ok(r)) => FormulaValue::Number(l - r),
                (Err(e), _) | (_, Err(e)) => FormulaValue::Error(e),
            },
            BinOp::Mul => match (left.as_number(), right.as_number()) {
                (Ok(l), Ok(r)) => FormulaValue::Number(l * r),
                (Err(e), _) | (_, Err(e)) => FormulaValue::Error(e),
            },
            BinOp::Div => match right.as_number() {
                Ok(0.0) => FormulaValue::Error(FormulaError::DivByZero),
                Ok(r) => match left.as_number() {
                    Ok(l) => FormulaValue::Number(l / r),
                    Err(e) => FormulaValue::Error(e),
                },
                Err(e) => FormulaValue::Error(e),
            },
            BinOp::Mod => match right.as_number() {
                Ok(0.0) => FormulaValue::Error(FormulaError::DivByZero),
                Ok(r) => match left.as_number() {
                    Ok(l) => FormulaValue::Number(l % r),
                    Err(e) => FormulaValue::Error(e),
                },
                Err(e) => FormulaValue::Error(e),
            },
            BinOp::Pow => match (left.as_number(), right.as_number()) {
                (Ok(l), Ok(r)) => FormulaValue::Number(l.powf(r)),
                (Err(e), _) | (_, Err(e)) => FormulaValue::Error(e),
            },
            BinOp::Eq => Self::eval_comparison_eq(&left, &right),
            BinOp::Ne => match Self::eval_comparison_eq(&left, &right) {
                FormulaValue::Boolean(b) => FormulaValue::Boolean(!b),
                other => other,
            },
            BinOp::Lt => Self::eval_comparison_ord(&left, &right, |l, r| l < r),
            BinOp::Gt => Self::eval_comparison_ord(&left, &right, |l, r| l > r),
            BinOp::Le => Self::eval_comparison_ord(&left, &right, |l, r| l <= r),
            BinOp::Ge => Self::eval_comparison_ord(&left, &right, |l, r| l >= r),
            BinOp::And | BinOp::Or => FormulaValue::Boolean(false), // handled above with short-circuit
        }
    }

    fn eval_comparison_eq(left: &FormulaValue, right: &FormulaValue) -> FormulaValue {
        match (left, right) {
            (FormulaValue::Number(l), FormulaValue::Number(r)) => FormulaValue::Boolean(*l == *r),
            (FormulaValue::Text(l), FormulaValue::Text(r)) => FormulaValue::Boolean(l == r),
            (FormulaValue::Boolean(l), FormulaValue::Boolean(r)) => FormulaValue::Boolean(l == r),
            (FormulaValue::Null, FormulaValue::Null) => FormulaValue::Boolean(true),
            (FormulaValue::Null, _) | (_, FormulaValue::Null) => FormulaValue::Boolean(false),
            _ => FormulaValue::Error(FormulaError::TypeError {
                expected: "matching types".into(),
                got: format!("{:?} vs {:?}", left, right),
                operation: "comparison".into(),
            }),
        }
    }

    fn eval_comparison_ord<F>(
        left: &FormulaValue,
        right: &FormulaValue,
        cmp: F,
    ) -> FormulaValue
    where
        F: Fn(f64, f64) -> bool,
    {
        match (left, right) {
            (FormulaValue::Number(l), FormulaValue::Number(r)) => FormulaValue::Boolean(cmp(*l, *r)),
            (FormulaValue::Text(l), FormulaValue::Text(r)) => {
                FormulaValue::Boolean(cmp(l.cmp(r) as i32 as f64, 0.0))
            }
            _ => FormulaValue::Error(FormulaError::TypeError {
                expected: "number or text".into(),
                got: format!("{:?} vs {:?}", left, right),
                operation: "comparison".into(),
            }),
        }
    }

    fn eval_function(
        name: &str,
        args: &[Expr],
        row_values: &HashMap<String, serde_json::Value>,
        all_rows: &[HashMap<String, serde_json::Value>],
    ) -> FormulaValue {
        match name {
            "SUM" | "AVG" | "COUNT" | "MIN" | "MAX" => {
                Self::eval_aggregate(name, args, row_values, all_rows)
            }
            "ABS" | "ROUND" | "CEIL" | "FLOOR" | "SQRT" => {
                Self::eval_math_single(name, args, row_values, all_rows)
            }
            "POW" | "MOD" => Self::eval_math_double(name, args, row_values, all_rows),
            "IF" => Self::eval_if(args, row_values, all_rows),
            "CONCAT" => Self::eval_concat(args, row_values, all_rows),
            "LEN" | "UPPER" | "LOWER" | "TRIM" => {
                Self::eval_string_func(name, args, row_values, all_rows)
            }
            _ => FormulaValue::Error(FormulaError::NameError(name.to_string())),
        }
    }

    fn eval_aggregate(
        name: &str,
        args: &[Expr],
        row_values: &HashMap<String, serde_json::Value>,
        all_rows: &[HashMap<String, serde_json::Value>],
    ) -> FormulaValue {
        // Support both: aggregate over field reference (single arg) and variadic literal args
        if args.len() == 1 {
            if let Expr::FieldRef(field_name) = &args[0] {
                let values: Vec<f64> = all_rows
                    .iter()
                    .filter_map(|r| {
                        r.get(field_name).and_then(|v| {
                            let fv = Self::json_to_formula_value(v);
                            fv.as_number().ok()
                        })
                    })
                    .collect();

                return match name {
                    "SUM" => FormulaValue::Number(values.iter().sum()),
                    "AVG" => {
                        if values.is_empty() {
                            FormulaValue::Number(0.0)
                        } else {
                            FormulaValue::Number(values.iter().sum::<f64>() / values.len() as f64)
                        }
                    }
                    "COUNT" => FormulaValue::Number(values.len() as f64),
                    "MIN" => {
                        FormulaValue::Number(values.iter().cloned().fold(f64::INFINITY, f64::min))
                    }
                    "MAX" => FormulaValue::Number(
                        values
                            .iter()
                            .cloned()
                            .fold(f64::NEG_INFINITY, f64::max),
                    ),
                    _ => FormulaValue::Error(FormulaError::NameError(name.to_string())),
                };
            }
        }

        // Variadic mode: evaluate each argument and aggregate the numeric results
        let values: Vec<f64> = args
            .iter()
            .filter_map(|arg| {
                let val = Self::eval(arg, row_values, all_rows);
                val.as_number().ok()
            })
            .collect();

        match name {
            "SUM" => FormulaValue::Number(values.iter().sum()),
            "AVG" => {
                if values.is_empty() {
                    FormulaValue::Number(0.0)
                } else {
                    FormulaValue::Number(values.iter().sum::<f64>() / values.len() as f64)
                }
            }
            "COUNT" => FormulaValue::Number(values.len() as f64),
            "MIN" => FormulaValue::Number(values.iter().cloned().fold(f64::INFINITY, f64::min)),
            "MAX" => FormulaValue::Number(
                values
                    .iter()
                    .cloned()
                    .fold(f64::NEG_INFINITY, f64::max),
            ),
            _ => FormulaValue::Error(FormulaError::NameError(name.to_string())),
        }
    }

    fn eval_math_single(
        name: &str,
        args: &[Expr],
        row_values: &HashMap<String, serde_json::Value>,
        all_rows: &[HashMap<String, serde_json::Value>],
    ) -> FormulaValue {
        if args.len() != 1 {
            return FormulaValue::Error(FormulaError::ValueError(format!(
                "{} expects exactly 1 argument",
                name
            )));
        }
        let val = Self::eval(&args[0], row_values, all_rows);
        let n = match val.as_number() {
            Ok(n) => n,
            Err(e) => return FormulaValue::Error(e),
        };
        match name {
            "ABS" => FormulaValue::Number(n.abs()),
            "ROUND" => FormulaValue::Number(n.round()),
            "CEIL" => FormulaValue::Number(n.ceil()),
            "FLOOR" => FormulaValue::Number(n.floor()),
            "SQRT" => {
                if n < 0.0 {
                    FormulaValue::Error(FormulaError::ValueError(
                        "Cannot take square root of negative number".to_string(),
                    ))
                } else {
                    FormulaValue::Number(n.sqrt())
                }
            }
            _ => FormulaValue::Error(FormulaError::NameError(name.to_string())),
        }
    }

    fn eval_math_double(
        name: &str,
        args: &[Expr],
        row_values: &HashMap<String, serde_json::Value>,
        all_rows: &[HashMap<String, serde_json::Value>],
    ) -> FormulaValue {
        if args.len() != 2 {
            return FormulaValue::Error(FormulaError::ValueError(format!(
                "{} expects exactly 2 arguments",
                name
            )));
        }
        let lv = Self::eval(&args[0], row_values, all_rows);
        let rv = Self::eval(&args[1], row_values, all_rows);
        let l = match lv.as_number() {
            Ok(n) => n,
            Err(e) => return FormulaValue::Error(e),
        };
        let r = match rv.as_number() {
            Ok(n) => n,
            Err(e) => return FormulaValue::Error(e),
        };
        match name {
            "POW" => FormulaValue::Number(l.powf(r)),
            "MOD" => {
                if r == 0.0 {
                    FormulaValue::Error(FormulaError::DivByZero)
                } else {
                    FormulaValue::Number(l % r)
                }
            }
            _ => FormulaValue::Error(FormulaError::NameError(name.to_string())),
        }
    }

    fn eval_if(
        args: &[Expr],
        row_values: &HashMap<String, serde_json::Value>,
        all_rows: &[HashMap<String, serde_json::Value>],
    ) -> FormulaValue {
        if args.len() != 3 {
            return FormulaValue::Error(FormulaError::ValueError(
                "IF expects exactly 3 arguments".to_string(),
            ));
        }
        let cond = Self::eval(&args[0], row_values, all_rows);
        match cond.as_boolean() {
            Ok(true) => Self::eval(&args[1], row_values, all_rows),
            Ok(false) => Self::eval(&args[2], row_values, all_rows),
            Err(e) => FormulaValue::Error(e),
        }
    }

    fn eval_concat(
        args: &[Expr],
        row_values: &HashMap<String, serde_json::Value>,
        all_rows: &[HashMap<String, serde_json::Value>],
    ) -> FormulaValue {
        let mut result = String::new();
        for arg in args {
            let val = Self::eval(arg, row_values, all_rows);
            match val {
                FormulaValue::Text(s) => result.push_str(&s),
                FormulaValue::Number(n) => result.push_str(&format!("{}", n)),
                FormulaValue::Boolean(b) => result.push_str(&b.to_string()),
                FormulaValue::Null => {}
                FormulaValue::Error(e) => return FormulaValue::Error(e),
            }
        }
        FormulaValue::Text(result)
    }

    fn eval_string_func(
        name: &str,
        args: &[Expr],
        row_values: &HashMap<String, serde_json::Value>,
        all_rows: &[HashMap<String, serde_json::Value>],
    ) -> FormulaValue {
        if args.len() != 1 {
            return FormulaValue::Error(FormulaError::ValueError(format!(
                "{} expects exactly 1 argument",
                name
            )));
        }
        let val = Self::eval(&args[0], row_values, all_rows);
        let s = match val {
            FormulaValue::Text(s) => s,
            FormulaValue::Error(e) => return FormulaValue::Error(e),
            _ => {
                return FormulaValue::Error(FormulaError::TypeError {
                    expected: "text".into(),
                    got: val.type_name().into(),
                    operation: name.to_string(),
                })
            }
        };
        match name {
            "LEN" => FormulaValue::Number(s.len() as f64),
            "UPPER" => FormulaValue::Text(s.to_uppercase()),
            "LOWER" => FormulaValue::Text(s.to_lowercase()),
            "TRIM" => FormulaValue::Text(s.trim().to_string()),
            _ => FormulaValue::Error(FormulaError::NameError(name.to_string())),
        }
    }

    fn json_to_formula_value(value: &serde_json::Value) -> FormulaValue {
        match value {
            serde_json::Value::Number(n) => FormulaValue::Number(n.as_f64().unwrap_or(0.0)),
            serde_json::Value::String(s) => FormulaValue::Text(s.clone()),
            serde_json::Value::Bool(b) => FormulaValue::Boolean(*b),
            serde_json::Value::Null => FormulaValue::Null,
            _ => FormulaValue::Null,
        }
    }
}

// ==================== Public API ====================

pub fn parse_formula(input: &str) -> Result<Expr, String> {
    let mut lexer = Lexer::new(input);
    let tokens = lexer.tokenize()?;
    let mut parser = Parser::new(tokens);
    parser.parse()
}

pub fn eval_formula(
    formula: &str,
    row_values: &HashMap<String, serde_json::Value>,
    all_rows: &[HashMap<String, serde_json::Value>],
) -> Result<serde_json::Value, String> {
    let expr = parse_formula(formula)?;
    let result = FormulaEvaluator::eval(&expr, row_values, all_rows);
    match result {
        FormulaValue::Error(e) => Err(format!("{:?}", e)),
        other => Ok(other.into_json()),
    }
}

/// Evaluate a formula and return the typed FormulaValue directly (for testing).
pub fn eval(formula: &str) -> FormulaValue {
    match parse_formula(formula) {
        Ok(expr) => FormulaEvaluator::eval(&expr, &HashMap::new(), &[]),
        Err(msg) => FormulaValue::Error(FormulaError::ValueError(msg)),
    }
}

#[cfg(test)]
// 测试约定：测试中使用 `.unwrap()` 是 Rust 惯用写法，由 `#[cfg(test)]` 门控，
// 不会编译进生产二进制。生产代码使用 `?` 运算符传播错误。
mod tests {
    use super::*;

    #[test]
    fn test_precedence() {
        assert_eq!(eval("1 + 2 * 3"), FormulaValue::Number(7.0));
        assert_eq!(eval("(1 + 2) * 3"), FormulaValue::Number(9.0));
        assert_eq!(eval("2 * 3 + 4 * 5"), FormulaValue::Number(26.0));
    }

    #[test]
    fn test_precedence_comparison() {
        assert_eq!(eval("1 + 2 > 2"), FormulaValue::Boolean(true));
        assert_eq!(eval("1 + 2 == 3"), FormulaValue::Boolean(true));
    }

    #[test]
    fn test_precedence_logical() {
        assert_eq!(eval("true || false && false"), FormulaValue::Boolean(true));
        assert_eq!(eval("(true || false) && false"), FormulaValue::Boolean(false));
    }

    #[test]
    fn test_power_precedence() {
        assert_eq!(eval("2 ^ 3 ^ 2"), FormulaValue::Number(512.0)); // right-associative: 2^(3^2) = 2^9 = 512
    }

    #[test]
    fn test_division_by_zero() {
        assert_eq!(eval("1 / 0"), FormulaValue::Error(FormulaError::DivByZero));
        assert_eq!(eval("10 % 0"), FormulaValue::Error(FormulaError::DivByZero));
    }

    #[test]
    fn test_type_error() {
        match eval("\"abc\" + 123") {
            FormulaValue::Error(FormulaError::TypeError { .. }) => {}
            other => panic!("Expected TypeError, got {:?}", other),
        }
    }

    #[test]
    fn test_case_insensitive() {
        assert_eq!(eval("sum(1, 2, 3)"), FormulaValue::Number(6.0));
        assert_eq!(eval("SUM(1, 2, 3)"), FormulaValue::Number(6.0));
        assert_eq!(eval("Sum(1, 2, 3)"), FormulaValue::Number(6.0));
    }

    #[test]
    fn test_arithmetic() {
        let result = eval_formula("1 + 2 * 3", &HashMap::new(), &[]).unwrap();
        assert_eq!(result, serde_json::json!(7.0));
    }

    #[test]
    fn test_field_ref() {
        let mut row = HashMap::new();
        row.insert("price".to_string(), serde_json::json!(100));
        row.insert("quantity".to_string(), serde_json::json!(3));
        let result = eval_formula("price * quantity", &row, &[]).unwrap();
        assert_eq!(result, serde_json::json!(300.0));
    }

    #[test]
    fn test_aggregate_sum() {
        let row = HashMap::new();
        let all_rows = vec![
            HashMap::from([("score".to_string(), serde_json::json!(10))]),
            HashMap::from([("score".to_string(), serde_json::json!(20))]),
            HashMap::from([("score".to_string(), serde_json::json!(30))]),
        ];
        let result = eval_formula("SUM(score)", &row, &all_rows).unwrap();
        assert_eq!(result, serde_json::json!(60.0));
    }

    #[test]
    fn test_aggregate_avg() {
        let row = HashMap::new();
        let all_rows = vec![
            HashMap::from([("score".to_string(), serde_json::json!(10))]),
            HashMap::from([("score".to_string(), serde_json::json!(20))]),
            HashMap::from([("score".to_string(), serde_json::json!(30))]),
        ];
        let result = eval_formula("AVG(score)", &row, &all_rows).unwrap();
        assert_eq!(result, serde_json::json!(20.0));
    }

    #[test]
    fn test_aggregate_case_insensitive() {
        let row = HashMap::new();
        let all_rows = vec![
            HashMap::from([("score".to_string(), serde_json::json!(10))]),
            HashMap::from([("score".to_string(), serde_json::json!(20))]),
            HashMap::from([("score".to_string(), serde_json::json!(30))]),
        ];
        let result = eval_formula("sum(score)", &row, &all_rows).unwrap();
        assert_eq!(result, serde_json::json!(60.0));
    }

    #[test]
    fn test_division_by_zero_error() {
        let result = eval_formula("1 / 0", &HashMap::new(), &[]);
        assert!(result.is_err());
    }

    #[test]
    fn test_unary_negation() {
        assert_eq!(eval("-5"), FormulaValue::Number(-5.0));
        assert_eq!(eval("-(3 + 2)"), FormulaValue::Number(-5.0));
    }

    #[test]
    fn test_unary_not() {
        assert_eq!(eval("!true"), FormulaValue::Boolean(false));
        assert_eq!(eval("!false"), FormulaValue::Boolean(true));
        assert_eq!(eval("NOT true"), FormulaValue::Boolean(false));
    }

    #[test]
    fn test_comparison_operators() {
        assert_eq!(eval("1 < 2"), FormulaValue::Boolean(true));
        assert_eq!(eval("2 > 1"), FormulaValue::Boolean(true));
        assert_eq!(eval("1 <= 1"), FormulaValue::Boolean(true));
        assert_eq!(eval("1 >= 2"), FormulaValue::Boolean(false));
        assert_eq!(eval("1 == 1"), FormulaValue::Boolean(true));
        assert_eq!(eval("1 != 2"), FormulaValue::Boolean(true));
    }

    #[test]
    fn test_logical_operators() {
        assert_eq!(eval("true && true"), FormulaValue::Boolean(true));
        assert_eq!(eval("true && false"), FormulaValue::Boolean(false));
        assert_eq!(eval("false || true"), FormulaValue::Boolean(true));
        assert_eq!(eval("false || false"), FormulaValue::Boolean(false));
    }

    #[test]
    fn test_modulo() {
        assert_eq!(eval("10 % 3"), FormulaValue::Number(1.0));
    }

    #[test]
    fn test_power() {
        assert_eq!(eval("2 ^ 10"), FormulaValue::Number(1024.0));
    }

    #[test]
    fn test_boolean_values() {
        assert_eq!(eval("true"), FormulaValue::Boolean(true));
        assert_eq!(eval("false"), FormulaValue::Boolean(false));
    }

    #[test]
    fn test_null_value() {
        assert_eq!(eval("null"), FormulaValue::Null);
    }

    #[test]
    fn test_text_concat() {
        assert_eq!(
            eval("\"hello\" + \"world\""),
            FormulaValue::Text("helloworld".to_string())
        );
    }

    #[test]
    fn test_unknown_function() {
        match eval("UNKNOWN(1)") {
            FormulaValue::Error(FormulaError::NameError(_)) => {}
            other => panic!("Expected NameError, got {:?}", other),
        }
    }

    #[test]
    fn test_if_function() {
        assert_eq!(eval("IF(1 > 0, 10, 20)"), FormulaValue::Number(10.0));
        assert_eq!(eval("IF(1 < 0, 10, 20)"), FormulaValue::Number(20.0));
    }

    #[test]
    fn test_abs_function() {
        assert_eq!(eval("ABS(-5)"), FormulaValue::Number(5.0));
    }

    #[test]
    fn test_string_functions() {
        assert_eq!(eval("LEN(\"hello\")"), FormulaValue::Number(5.0));
        assert_eq!(eval("UPPER(\"hello\")"), FormulaValue::Text("HELLO".to_string()));
        assert_eq!(eval("LOWER(\"HELLO\")"), FormulaValue::Text("hello".to_string()));
        assert_eq!(eval("TRIM(\"  hi  \")"), FormulaValue::Text("hi".to_string()));
    }
}
