use serde_json;
use std::collections::HashMap;

#[derive(Debug, Clone, PartialEq)]
pub enum Token {
    Number(f64),
    String(String),
    FieldRef(String),
    Plus,
    Minus,
    Multiply,
    Divide,
    LParen,
    RParen,
    Comma,
    FuncSum,
    FuncAvg,
    FuncCount,
    FuncMin,
    FuncMax,
}

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
        return ch;
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
        self.advance();
        let start = self.position;
        while let Some(ch) = self.peek() {
            if *ch == '"' {
                break;
            }
            self.advance();
        }
        let s: String = self.input[start..self.position].iter().collect();
        self.advance();
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
                        '+' => { self.advance(); Token::Plus }
                        '-' => { self.advance(); Token::Minus }
                        '*' => { self.advance(); Token::Multiply }
                        '/' => { self.advance(); Token::Divide }
                        '(' => { self.advance(); Token::LParen }
                        ')' => { self.advance(); Token::RParen }
                        ',' => { self.advance(); Token::Comma }
                        '"' => Token::String(self.read_string()),
                        '0'..='9' => Token::Number(self.read_number()),
                        c if c.is_alphabetic() || *c == '_' => {
                            let ident = self.read_identifier();
                            match ident.to_uppercase().as_str() {
                                "SUM" => Token::FuncSum,
                                "AVG" => Token::FuncAvg,
                                "COUNT" => Token::FuncCount,
                                "MIN" => Token::FuncMin,
                                "MAX" => Token::FuncMax,
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

#[derive(Debug, Clone)]
pub enum Expr {
    Number(f64),
    String(String),
    FieldRef(String),
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
}

pub struct Parser {
    tokens: Vec<Token>,
    position: usize,
}

impl Parser {
    pub fn new(tokens: Vec<Token>) -> Self {
        Self { tokens, position: 0 }
    }

    fn peek(&self) -> Option<&Token> {
        self.tokens.get(self.position)
    }

    fn advance(&mut self) -> Option<Token> {
        let tok = self.tokens.get(self.position).cloned();
        self.position += 1;
        tok
    }

    pub fn parse(&mut self) -> Result<Expr, String> {
        self.parse_additive()
    }

    fn parse_additive(&mut self) -> Result<Expr, String> {
        let mut left = self.parse_multiplicative()?;
        loop {
            match self.peek() {
                Some(Token::Plus) => {
                    self.advance();
                    let right = self.parse_multiplicative()?;
                    left = Expr::BinaryOp { left: Box::new(left), op: BinOp::Add, right: Box::new(right) };
                }
                Some(Token::Minus) => {
                    self.advance();
                    let right = self.parse_multiplicative()?;
                    left = Expr::BinaryOp { left: Box::new(left), op: BinOp::Sub, right: Box::new(right) };
                }
                _ => break,
            }
        }
        Ok(left)
    }

    fn parse_multiplicative(&mut self) -> Result<Expr, String> {
        let mut left = self.parse_primary()?;
        loop {
            match self.peek() {
                Some(Token::Multiply) => {
                    self.advance();
                    let right = self.parse_primary()?;
                    left = Expr::BinaryOp { left: Box::new(left), op: BinOp::Mul, right: Box::new(right) };
                }
                Some(Token::Divide) => {
                    self.advance();
                    let right = self.parse_primary()?;
                    left = Expr::BinaryOp { left: Box::new(left), op: BinOp::Div, right: Box::new(right) };
                }
                _ => break,
            }
        }
        Ok(left)
    }

    fn parse_primary(&mut self) -> Result<Expr, String> {
        match self.peek().cloned() {
            Some(Token::Number(n)) => {
                self.advance();
                Ok(Expr::Number(n))
            }
            Some(Token::String(s)) => {
                self.advance();
                Ok(Expr::String(s))
            }
            Some(Token::FieldRef(name)) => {
                self.advance();
                if matches!(self.peek(), Some(Token::LParen)) {
                    return Err(format!("Unknown function: {}", name));
                }
                Ok(Expr::FieldRef(name))
            }
            Some(Token::FuncSum) | Some(Token::FuncAvg) | Some(Token::FuncCount)
            | Some(Token::FuncMin) | Some(Token::FuncMax) => {
                let func_token = self.advance().unwrap();
                let name = match func_token {
                    Token::FuncSum => "SUM",
                    Token::FuncAvg => "AVG",
                    Token::FuncCount => "COUNT",
                    Token::FuncMin => "MIN",
                    Token::FuncMax => "MAX",
                    _ => unreachable!(),
                };
                self.advance();
                let mut args = vec![self.parse_additive()?];
                while matches!(self.peek(), Some(Token::Comma)) {
                    self.advance();
                    args.push(self.parse_additive()?);
                }
                match self.advance() {
                    Some(Token::RParen) => {}
                    _ => return Err("Expected closing parenthesis".to_string()),
                }
                Ok(Expr::FuncCall { name: name.to_string(), args })
            }
            Some(Token::LParen) => {
                self.advance();
                let expr = self.parse_additive()?;
                match self.advance() {
                    Some(Token::RParen) => Ok(expr),
                    _ => Err("Expected closing parenthesis".to_string()),
                }
            }
            Some(Token::Minus) => {
                self.advance();
                let expr = self.parse_primary()?;
                Ok(Expr::BinaryOp {
                    left: Box::new(Expr::Number(0.0)),
                    op: BinOp::Sub,
                    right: Box::new(expr),
                })
            }
            other => Err(format!("Unexpected token: {:?}", other)),
        }
    }
}

pub struct FormulaEvaluator;

impl FormulaEvaluator {
    pub fn eval(
        expr: &Expr,
        row_values: &HashMap<String, serde_json::Value>,
        all_rows: &[HashMap<String, serde_json::Value>],
    ) -> Result<serde_json::Value, String> {
        match expr {
            Expr::Number(n) => Ok(serde_json::Value::Number(
                serde_json::Number::from_f64(*n).unwrap_or(serde_json::Number::from(0)),
            )),
            Expr::String(s) => Ok(serde_json::Value::String(s.clone())),
            Expr::FieldRef(name) => Ok(row_values.get(name).cloned().unwrap_or(serde_json::Value::Null)),
            Expr::BinaryOp { left, op, right } => {
                let l = Self::eval(left, row_values, all_rows)?;
                let r = Self::eval(right, row_values, all_rows)?;
                let lv = Self::to_f64(&l);
                let rv = Self::to_f64(&r);
                let result = match op {
                    BinOp::Add => lv + rv,
                    BinOp::Sub => lv - rv,
                    BinOp::Mul => lv * rv,
                    BinOp::Div => {
                        if rv == 0.0 {
                            return Err("Division by zero".to_string());
                        }
                        lv / rv
                    }
                };
                Ok(serde_json::Value::Number(
                    serde_json::Number::from_f64(result).unwrap_or(serde_json::Number::from(0)),
                ))
            }
            Expr::FuncCall { name, args } => {
                if args.len() != 1 {
                    return Err(format!("{} expects exactly 1 argument", name));
                }
                let field_expr = &args[0];
                let field_name = match field_expr {
                    Expr::FieldRef(n) => n.clone(),
                    _ => return Err("Aggregate functions require a field reference".to_string()),
                };

                let values: Vec<f64> = all_rows
                    .iter()
                    .filter_map(|r| r.get(&field_name).map(Self::to_f64))
                    .collect();

                let result = match name.as_str() {
                    "SUM" => values.iter().sum(),
                    "AVG" => {
                        if values.is_empty() {
                            0.0
                        } else {
                            values.iter().sum::<f64>() / values.len() as f64
                        }
                    }
                    "COUNT" => values.len() as f64,
                    "MIN" => values.iter().cloned().fold(f64::INFINITY, f64::min),
                    "MAX" => values.iter().cloned().fold(f64::NEG_INFINITY, f64::max),
                    _ => return Err(format!("Unknown function: {}", name)),
                };

                Ok(serde_json::Value::Number(
                    serde_json::Number::from_f64(result).unwrap_or(serde_json::Number::from(0)),
                ))
            }
        }
    }

    fn to_f64(value: &serde_json::Value) -> f64 {
        match value {
            serde_json::Value::Number(n) => n.as_f64().unwrap_or(0.0),
            serde_json::Value::String(s) => s.parse().unwrap_or(0.0),
            _ => 0.0,
        }
    }
}

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
    FormulaEvaluator::eval(&expr, row_values, all_rows)
}

#[cfg(test)]
mod tests {
    use super::*;

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
    fn test_division_by_zero() {
        let result = eval_formula("1 / 0", &HashMap::new(), &[]);
        assert!(result.is_err());
    }
}
